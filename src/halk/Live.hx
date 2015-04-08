package halk;

import haxe.Unserializer;
import halk.Macro.MacroContext;
import haxe.Http;

#if sys
import sys.io.File;
#else
import haxe.Timer;
#end

using StringTools;


class Live {

    static public var instance(default, null) = new Live();

    var listeners = new Array<Void->Void>();

    var interp:HalkInterp = new HalkInterp();

    var data:MacroContext;

    var methods:Map<String, Dynamic>;

    function new() {
        nextLoad();
    }

    inline function nextLoad() {
        delayedCall(load, 1000);
    }

    function load() {
        #if sys
//        trace(FileSystem.readDirectory(Sys.getCwd()));
        var data:String = null;
        try {
            data = File.getContent("data.live");
        } catch (e:Dynamic) {
            onError(e);
            return;
        }
        onData(data);
        #else
        var loader = new Http("data.live");
        loader.onData = onData;
        loader.onError = onError;
        loader.request();
        #end
    }

    function onData(data:String) {
        nextLoad();
        process(data);
    }

    function onError(e:Dynamic) {
        trace(e);
        nextLoad();
    }

    function process(str:String):Void {
        if (str == null) return;

        if (data != null && data.version == MacroContext.getVersion(str)) {
            return;
        }

        var newData:MacroContext = MacroContext.fromFile(str);

        if (newData == null) {
            return;
        }

        data = newData;

        interp = new HalkInterp();
        var vars:Map<String, Dynamic> = interp.variables;

        for (n in data.types.keys()) {
            var t:Array<String> = data.types[n];
            var type = Type.resolveClass(n);
            if (type == null) continue;

            var name = t.pop();
            var end = null;
            for (s in t) {
                if (end == null) {
                    vars.set(s, end = {});
                }
                else if (!Reflect.hasField(end, s)) {
                    Reflect.setField(end, s, end = {});
                }
            }
            if (end == null) {
                vars.set(n, type);
            } else {
                Reflect.setField(end, name, type);
            }
        }

        methods = [for (m in data.methods.keys()) m => interp.execute(data.methods[m])];

        updateListeners();
    }

    @:keep public function call<T>(ethis:T, method:String, args:Array<Dynamic>):Dynamic {
        if (data == null) return null;
        trace("call " + method);
        interp.variables.set("this", ethis);
        return Reflect.callMethod(ethis, methods.get(method), args);
    }

    public function addListener(listener:Void->Void):Void {
        trace('register listener $listener');
        removeListener(listener);
        listeners.push(listener);
    }

    public function removeListener(listener:Void->Void):Void {
        if (listeners.remove(listener)) {
            trace('unregister listener $listener');
        }
    }

    function updateListeners() {
        for (l in listeners.copy()) l();
    }

    static function delayedCall(f:Void->Void, time:Int) {
        #if sys
        #if neko neko.vm.Thread #else cpp.vm.Thread #end
        .create(function() {
            Sys.sleep(time / 1000);
            f();
        });
        #else
        Timer.delay(f, time);
        #end
    }
}
