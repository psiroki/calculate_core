enum _Kind {
  number,
  add,
  subtract,
  multiply,
  divide,
  identifier,
  assign,
  openBracket,
  closeBracket,
}

abstract class CalculationContext {
  factory CalculationContext() => new _DefaultCalculationContext();
  _StackElement pop();
  void push(_StackElement newElement);

  num operator [](String registerName);
  void operator []=(String registerName, num value);
}

abstract class _StackCalculationContext implements CalculationContext {
  _StackElement pop() => _stack.removeLast();
  void push(_StackElement newElement) {
    _stack.add(newElement.bind(this));
  }

  final List<_StackElement> _stack = [];
}

class _DefaultCalculationContext extends _StackCalculationContext {
  num operator [](String registerName) => _registers[registerName];
  void operator []=(String registerName, num value) {
    _registers[registerName] = value;
  }

  final Map<String, num> _registers = {};
}

class _OptimizationContext extends _StackCalculationContext {
  num operator [](String registerName) {
    _registerAccess = true;
    return 1;
  }

  void operator []=(String registerName, num value) {
    _registerAccess = true;
  }

  _StackElement pop() {
    _StackElement result = super.pop();
    _popped.add(result);
    return result;
  }

  void push(_StackElement newElement) {
    if (_registerAccess) {
      newElement = new _VariableReference("**unknown**", this);
      _registerAccess = false;
    }
    _popped.clear();
    super.push(newElement);
  }

  num get stackDepth => _stack.length;
  bool get stackIsNotEmpty => _stack.isNotEmpty;
  bool get topIsLiteral => _stack.last is _Literal;
  num get topValue => (_stack.last as _Literal).value;

  Iterable<_StackElement> stackSince(int start) => _stack.skip(start);

  bool _registerAccess = false;
  List<_StackElement> _popped = [];
}

abstract class _StackElement {
  num get value;
  void set value(num val);
  _Opcode toOpcode();

  _StackElement bind(CalculationContext context);
}

class _VariableReference extends _StackElement {
  _VariableReference(this.name, [this.context]);

  num get value => context[name] ?? 0;
  void set value(num val) {
    context[name] = val;
  }

  _Opcode toOpcode() => new _Opcode()
    ..kind = _Kind.identifier
    ..value = name;

  _VariableReference bind(CalculationContext context) =>
      new _VariableReference(name, context);

  final String name;
  final CalculationContext context;
}

class _Literal extends _StackElement {
  _Literal(this._value);

  num get value => _value;

  void set value(num val) {
    throw "You can't set a value to a literal";
  }

  _Opcode toOpcode() => new _Opcode()
    ..kind = _Kind.number
    ..value = _value;

  _Literal bind(CalculationContext context) => this;

  final num _value;
}

typedef void _PerformOperation(_Opcode op, CalculationContext n);
typedef _Opcode _ToOpcode(_Token token);

class _KindDefinition {
  _KindDefinition(this.kind, this.singleCharacter,
      [this.perform, _ToOpcode toOpcode])
      : this._toOpcodeOverride = toOpcode;

  _Opcode toOpcode(_Token token) {
    if (_toOpcodeOverride != null) return _toOpcodeOverride(token);
    return new _Opcode()
      ..kind = token.kind
      ..value = token.value;
  }

  final _Kind kind;
  final String singleCharacter;
  final _PerformOperation perform;
  final _ToOpcode _toOpcodeOverride;
}

final List<_KindDefinition> _tokenDefinitions = new List.unmodifiable([
  new _KindDefinition(_Kind.add, "+", (_Opcode op, CalculationContext n) {
    n.push(new _Literal(n.pop().value + n.pop().value));
  }),
  new _KindDefinition(_Kind.subtract, "-", (_Opcode op, CalculationContext n) {
    n.push(new _Literal(-n.pop().value + n.pop().value));
  }),
  new _KindDefinition(_Kind.multiply, "*", (_Opcode op, CalculationContext n) {
    n.push(new _Literal(n.pop().value * n.pop().value));
  }),
  new _KindDefinition(_Kind.divide, "/", (_Opcode op, CalculationContext n) {
    num a = n.pop().value, b = n.pop().value;
    n.push(new _Literal(b / a));
  }),
  new _KindDefinition(_Kind.number, null, (_Opcode op, CalculationContext n) {
    n.push(new _Literal(op.value as num));
  },
      (_Token token) => new _Opcode()
        ..kind = token.kind
        ..value = num.parse(token.value)),
  new _KindDefinition(_Kind.identifier, null,
      (_Opcode op, CalculationContext n) {
    n.push(new _VariableReference(op.value));
  }),
  new _KindDefinition(_Kind.assign, "=", (_Opcode op, CalculationContext n) {
    num value = n.pop().value;
    _VariableReference target = n.pop() as _VariableReference;
    target.value = value;
    n.push(new _Literal(value));
  }),
  new _KindDefinition(_Kind.openBracket, "("),
  new _KindDefinition(_Kind.closeBracket, ")"),
]);
final Map<_Kind, _KindDefinition> _kindDefs = new Map.unmodifiable(
    new Map.fromIterable(_tokenDefinitions, key: (t) => t.kind));

final Map<String, _Kind> _singleCharacterTokens = new Map.unmodifiable(
    new Map.fromIterable(
        _kindDefs.keys.where((k) => _kindDefs[k].singleCharacter != null),
        key: (k) => _kindDefs[k].singleCharacter));

String kindToString(_Kind kind) {
  String kindString = kind.toString();
  int dot = kindString.indexOf('.');
  if (dot < 0) return kindString;
  return kindString.substring(dot + 1);
}

abstract class _Kindful {
  _Kind get kind;
}

class _Token implements _Kindful {
  String toString() => "${kindToString(kind)}(${value??''})";
  _Opcode toOpcode() => _kindDefs[kind].toOpcode(this);
  _Kind kind;
  String value;
}

class _Opcode implements _Kindful {
  String toString() => "${kindToString(kind)}${value!=null?' ':''}${value??''}";
  void perform(CalculationContext context) =>
      _kindDefs[kind].perform(this, context);
  _Kind kind;
  Object value;
}

final Map<_Kind, RegExp> _patternTokens = new Map.unmodifiable({
  _Kind.number: new RegExp(r"(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?"),
  _Kind.identifier: new RegExp(r"[_a-zA-Z][_a-zA-Z0-9]*"),
});

Iterable<_Token> _tokenize(String buffer) sync* {
  final int l = buffer.length;
  for (int i = 0; i < l; ++i) {
    if (buffer[i] == " ") continue;
    _Kind single = _singleCharacterTokens[buffer[i]];
    if (single == null) {
      bool found = false;
      for (_Kind k in _patternTokens.keys) {
        RegExp re = _patternTokens[k];
        if (buffer.startsWith(re, i)) {
          found = true;
          String match = re.stringMatch(buffer.substring(i));
          yield new _Token()
            ..kind = k
            ..value = match;
          i += match.length - 1;
          break;
        }
      }
      if (found == null) throw "Found a strange character in the source";
    } else {
      yield new _Token()..kind = single;
    }
  }
}

int _valueExpression(List<_Opcode> ops, List<_Token> tokens, int cursor) {
  _Token current = tokens[cursor];
  if (current.kind == _Kind.openBracket) {
    cursor = _expression.expression(ops, tokens, cursor + 1);
    if (tokens[cursor].kind != _Kind.closeBracket)
      throw "Ouch, no closing bracket";
    return cursor + 1;
  }
  if (current.kind == _Kind.identifier) {
    ops.add(tokens[cursor].toOpcode());
  } else {
    if (current.kind == _Kind.subtract) ++cursor;
    assert(tokens[cursor].kind == _Kind.number);
    ops.add((tokens[cursor]
      ..value = "${current.kind == _Kind.subtract ? '-' : ''}"
          "${tokens[cursor].value}").toOpcode());
  }
  return cursor + 1;
}

class _PrecedenceGroup {
  _PrecedenceGroup(Iterable<_Kind> kinds, [this.parent])
      : this.kinds = kinds.toSet();

  int halfExpression(List<_Opcode> ops, List<_Token> tokens, int cursor) {
    _Token opToken = null;
    if (this.kinds.contains(tokens[cursor].kind)) {
      // E => E + T
      opToken = tokens[cursor];
    } else {
      // this is not an expression, E => T
      return cursor;
    }

    return expression(ops, tokens, cursor + 1, opToken);
  }

  int expression(List<_Opcode> ops, List<_Token> tokens, int cursor,
      [_Token lastTokenOp]) {
    int afterTerm = parent == null
        ? _valueExpression(ops, tokens, cursor)
        : parent.expression(ops, tokens, cursor);
    if (lastTokenOp != null) ops.add(lastTokenOp.toOpcode());
    if (afterTerm < tokens.length)
      return halfExpression(ops, tokens, afterTerm);
    return afterTerm;
  }

  _PrecedenceGroup over(Iterable<_Kind> kinds) =>
      new _PrecedenceGroup(kinds, this);

  final _PrecedenceGroup parent;
  final Set<_Kind> kinds;
}

_PrecedenceGroup _expression =
    new _PrecedenceGroup([_Kind.multiply, _Kind.divide])
        .over([_Kind.add, _Kind.subtract]).over([_Kind.assign]);

int _parseTokens(List<_Opcode> ops, List<_Token> tokens, int cursor) {
  return _expression.expression(ops, tokens, cursor);
}

class Program {
  /// Creates a program by parsing a source expression.
  Program(String source) {
    _parseTokens(_ops, _tokenize(source).toList(growable: false), 0);
  }

  Program._fromOps(List<_Opcode> ops) : _ops = new List.unmodifiable(ops);

  /// Executes the program in the given calculaton context.
  num execute([CalculationContext context]) {
    if (context == null) context = new CalculationContext();
    for (_Opcode op in _ops) {
      op.perform(context);
    }
    return context.pop().value;
  }

  /// Returns an optimized version of the program if possible.
  /// Tries to calculate as much as it can in advance.
  Program optimize() {
    _OptimizationContext context = new _OptimizationContext();
    // new, optimized opcodes
    List<_Opcode> newOps = [];
    // the bound to which we have already added the opcodes
    // we don't automatically add opcodes for contextfree calculations,
    // only when needed, but we need to save where we have to
    // build the stack when we do have to
    int stackBound = 0;
    // we save the stack from the last written opcode before the operation,
    // so if the operation taints the stack, we emit this, and emit the
    // opcode that tainted the stack
    List<_StackElement> stackSave = null;
    for (_Opcode op in _ops) {
      if (context.stackIsNotEmpty && context.topIsLiteral)
        stackSave = context.stackSince(stackBound).toList(growable: false);
      else
        stackSave = null;
      op.perform(context);
      if (!context.topIsLiteral) {
        // the expression has referred to a variable
        if (stackSave != null && stackSave.isNotEmpty) {
          // since we added the last opcode, these entries were added to the
          // stack
          newOps.addAll(stackSave.map((e) => e.toOpcode()));
        }
        newOps.add(op);
        stackBound = context.stackDepth;
      }
    }
    if (context.topIsLiteral) {
      // the expression refers to no variable
      return new Program._fromOps([
        new _Opcode()
          ..kind = _Kind.number
          ..value = context.topValue
      ]);
    }
    if (newOps.length < _ops.length) return new Program._fromOps(newOps);
    // could not optimize
    return this;
  }

  int get numOpcodes => _ops.length;

  /// Provides a stirng representation of the program by listing
  /// the opcodes seperated by newlines.
  String toString() => _ops.join("\n");

  List<_Opcode> _ops = [];
}
