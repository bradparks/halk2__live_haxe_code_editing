package halk.macro;

import haxe.macro.Type;
import haxe.macro.Expr;
import haxe.macro.Context;
import hscript.Expr;
import halk.macro.TypeTools;

using hscript.Printer;
using haxe.macro.Tools;

class HScriptTypedConverter {

    var binops:Map<Binop, String>;
    var unops:Map<Unop, String>;

    var types:Map<String, Array<String>>;

    public function new() {

        binops = new Map();
        unops = new Map();
        for( c in std.Type.getEnumConstructs(Binop) ) {
            if( c == "OpAssignOp" ) continue;
            var op = std.Type.createEnum(Binop, c);
            var assign = false;
            var str = switch( op ) {
                case OpAdd: assign = true;  "+";
                case OpMult: assign = true; "*";
                case OpDiv: assign = true; "/";
                case OpSub: assign = true; "-";
                case OpAssign: "=";
                case OpEq: "==";
                case OpNotEq: "!=";
                case OpGt: ">";
                case OpGte: ">=";
                case OpLt: "<";
                case OpLte: "<=";
                case OpAnd: assign = true; "&";
                case OpOr: assign = true; "|";
                case OpXor: assign = true; "^";
                case OpBoolAnd: "&&";
                case OpBoolOr: "||";
                case OpShl: assign = true; "<<";
                case OpShr: assign = true; ">>";
                case OpUShr: assign = true; ">>>";
                case OpMod: assign = true; "%";
                case OpAssignOp(_): "";
                case OpInterval: "...";
                case OpArrow: "=>";
            };
            binops.set(op, str);
            if( assign )
                binops.set(OpAssignOp(op), str + "=");
        }
        for( c in std.Type.getEnumConstructs(Unop) ) {
            var op = std.Type.createEnum(Unop, c);
            var str = switch( op ) {
                case OpNot: "!";
                case OpNeg: "-";
                case OpNegBits: "~";
                case OpIncrement: "++";
                case OpDecrement: "--";
            }
            unops.set(op, str);
        }
    }

    public function convert(type:ClassType, expr:TypedExpr):{e:hscript.Expr, types:Map<String, Array<String>>} {
        types = new Map();

//        trace(expr.toString());
        var e:hscript.Expr = map(expr);
//        trace(e.toString());
        //trace(e);
        return {e:e, types:types};
    }

    function map(e:TypedExpr):hscript.Expr {
        if (e == null) return null;

        inline function mapArray(arr:Array<TypedExpr>):Array<hscript.Expr> {
            return [for (p in arr) map(p)];
        }

        inline function registerStdType() {
            types.set("Type", ["Type"]);
        }

        inline function registerBaseType(type:BaseType):Void {
            var t = BaseTypeTools.baseTypePath(type);
            types.set(t.join("."), t);
        }

        return switch e.expr {
            case TConst(TInt(c)): EConst(CInt(c));
            case TConst(TFloat(c)): EConst(CFloat(Std.parseFloat(c)));
            case TConst(TString(c)): EConst(CString(c));
            case TConst(TBool(c)): EIdent(c ? "true" : "false");
            case TConst(TNull): EIdent("null");
            case TConst(TThis): EIdent("this");
            case TConst(TSuper): EIdent("super");
            case TLocal(v): convertType(e.t, e.pos); EIdent(v.name);
            case TArray(e1, e2): EArray(map(e1), map(e2));
            case TBinop(OpAssignOp(op), e1, e2): EBinop(binops.get(op) + "=", map(e1), map(e2));
            case TBinop(op, e1, e2): EBinop(binops.get(op), map(e1), map(e2));
            case TField(e, field):
                convertType(e.t, e.pos);
                var f = switch field {
                    case FInstance(_, t) | FStatic(_, t) | FAnon(t) | FClosure(_, t): t.get().name;
                    case FDynamic(s): s;
                    case FEnum(_, ef): ef.name;
                };
                EField(map(e), f);

            case TTypeExpr(cl):
                var baseType = baseTypeFromModuleType(cl);
                registerBaseType(baseType);
                var path = BaseTypeTools.baseTypePath(baseType);
                var res = EIdent(path.shift());
                while (path.length > 0) res = EField(res, path.shift());
                res;

            case TParenthesis(e): EParent(map(e));
            case TObjectDecl(fields): EObject([for (f in fields) {name:f.name, e:map(f.expr)}]);
            case TArrayDecl(el): EArrayDecl(mapArray(el));
            case TCall(e, params):
                switch e.expr {
                    case TField(f, FEnum(_, ef)):
                        convertType(f.t, f.pos);
                        registerStdType();
                        ECall(EField(EIdent("Type"), "createEnum"), [map(f), EConst(CString(ef.name)), EArrayDecl(mapArray(params))]);
                    case _:
                        convertType(e.t, e.pos);
                        ECall(map(e), mapArray(params));
                }

            case TNew(tp, _, params):
                var bs = tp.get();
                registerBaseType(bs);
                var path = BaseTypeTools.baseTypePath(bs);
                ENew(path.join("."), mapArray(params));
            
            case TUnop(op, postFix, e): EUnop(unops.get(op), postFix, map(e));
            case TFunction(func):
                var args = [];
                for (arg in func.args) {
                    if (arg.value != null) {
                        Context.warning("default args not implemented", e.pos);
                    }
                    args.push({name:arg.v.name, opt:arg.value != null, t:convertType(arg.v.t, e.pos) } ); // contertComplexType(arg.type, e.pos)
                }
                EFunction(args, map(func.expr), null, convertType(func.t, e.pos)); // ret type contertComplexType(func.ret, e.pos)

            case TVar(v, expr): EVar(v.name, convertType(v.t, e.pos), map(expr));
            case TBlock(el): EBlock(mapArray(el));
            case TFor(v, it, expr): EFor(v.name, map(it), map(expr));
            case TIf(econd, eif, eelse): EIf(map(econd), map(eif), map(eelse));
            case TWhile(econd, e, true): EWhile(map(econd), map(e));
            case TWhile(econd, e, false): Context.error("do{}while() not implemented", econd.pos); //EWhile(f(econd), map(e), normalWhile);
            case TSwitch(e, cases, edef):

                var res:Array<{values:Array<hscript.Expr>, expr:hscript.Expr}> = [];
                for (c in cases) {
                    res.push({expr:map(c.expr), values:mapArray(c.values)});
                }
                ESwitch(map(e), res, map(edef));

            case TPatMatch: throw "unknown expr";
            case TTry(etry, catches):
                if (catches.length > 1) {
                    Context.warning("halk support only first catch", e.pos);
                }
                var c = catches[0];
                ETry(map(etry), c.v.name, convertType(c.v.t, e.pos), map(c.expr));

            case TReturn(e): EReturn(map(e));
            case TBreak: EBreak;
            case TContinue: EContinue;
            case TThrow(e): EThrow(map(e));
            case TCast(e, t): registerBaseType(baseTypeFromModuleType(t)); map(e);
            case TMeta(_, e): map(e);
            case TEnumParameter(e1, _, idx):
                convertType(e1.t, e1.pos);
                registerStdType();
                EArray(ECall(EField(EIdent("Type"), "enumParameters"), [map(e1)]), EConst(CInt(idx)));
        };
    }

    function baseTypeFromModuleType(t:ModuleType):BaseType {
        return switch t {
            case TClassDecl(r): r.get();
            case TEnumDecl(r): var res = r.get();
                // patch for enums
                // haxe rename enums, remove module name from path
                // test.Module.EnumName -> test.EnumName
                var path = res.module.split(".");
                path.pop();
                res.module = path.join(".");
                res;
            case TTypeDecl(r): r.get();
            case TAbstract(r): r.get();
        }
    }

    inline function convertType(type:haxe.macro.Type, pos:Position):CType {
        return contertComplexType(TypeTools.toComplexType(type), pos);
    }

    function contertTypePath(p:TypePath, pos:Position):CType {
        var path = p.pack.length > 0 ? p.pack.concat([p.name]) : [p.name];
        try {
            var type = Context.getType(path.join("."));
            var fullPath = TypeTools.getFullPath(type);
            if (fullPath != null) {
                path = fullPath;
            }
        } catch (e:Dynamic) {}

        if (path[0] == "StdTypes") {
            path.shift();
        }
        if (path.length == 0) return null;

        types.set(path.join("."), path);
        return CTPath(path, null);
    }

    function contertComplexType(type:ComplexType, pos:Position):CType {
        if (type == null) return null;

        return switch type {
            case TPath(p):
                contertTypePath(p, pos);
            case TFunction(args, ret): CTFun([for (a in args) contertComplexType(a, pos)], contertComplexType(ret, pos));
            case TExtend(_, fields) | TAnonymous(fields):
                var res = [];
                for (f in fields) {
                    var name = f.name;
                    switch f.kind {
                        case FVar(t, e):
                            if (e != null) Context.error('default values are not supported in anonymous structs', pos);
                            res.push({name: name, t: contertComplexType(t, pos)});

                        case FProp(_, _):
                            Context.error('properties are not supported in anonymous structs', pos);

                        case FFun(f):
                            var type = CTFun([for (a in f.args) contertComplexType(a.type, pos)], contertComplexType(f.ret, pos));
                            res.push({name: name, t: type});
                    }
                }
                CTAnon(res);
            case TParent(t): CTParent(contertComplexType(t, pos));
            //case TExtend(p, fields): throw "not implemented"; // TODO: FIX: case TExtend(_, fields) | TAnonymous(fields):
            case TOptional(t): contertComplexType(t, pos);
        }
    }
}