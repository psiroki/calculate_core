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

class CalculationException implements Exception {
  CalculationException(this.message);

  @override
  String toString() => message;

  final String message;
}

class CalculationParseException extends CalculationException {
  CalculationParseException(String message, [this.buffer, this.offset])
      : super(message);

  final String? buffer;
  final int? offset;
}

abstract class CalculationContext {
  factory CalculationContext() => _DefaultCalculationContext();
  _StackElement pop();
  void push(_StackElement newElement);

  num? operator [](String registerName);
  void operator []=(String registerName, num value);
}

abstract class _StackCalculationContext implements CalculationContext {
  @override
  _StackElement pop() => _stack.removeLast();

  @override
  void push(_StackElement newElement) {
    _stack.add(newElement.bind(this));
  }

  final List<_StackElement> _stack = [];
}

class _DefaultCalculationContext extends _StackCalculationContext {
  @override
  num? operator [](String registerName) => _registers[registerName];

  @override
  void operator []=(String registerName, num value) {
    _registers[registerName] = value;
  }

  final Map<String, num> _registers = {};
}

class _OptimizationContext extends _StackCalculationContext {
  @override
  num operator [](String registerName) {
    _registerAccess = true;
    return 1;
  }

  @override
  void operator []=(String registerName, num value) {
    _registerAccess = true;
  }

  @override
  _StackElement pop() {
    final _StackElement result = super.pop();
    _popped.add(result);
    return result;
  }

  @override
  void push(_StackElement newElement) {
    _StackElement elementToPush = newElement;
    if (_registerAccess) {
      elementToPush = _VariableReference("**unknown**", this);
      _registerAccess = false;
    }
    _popped.clear();
    super.push(elementToPush);
  }

  int get stackDepth => _stack.length;
  bool get stackIsNotEmpty => _stack.isNotEmpty;
  bool get topIsLiteral => _stack.last is _Literal;
  num get topValue => (_stack.last as _Literal).value;

  Iterable<_StackElement> stackSince(int start) => _stack.skip(start);

  bool _registerAccess = false;
  final List<_StackElement> _popped = [];
}

abstract class _StackElement {
  num get value;
  set value(num val);
  _Opcode toOpcode();

  _StackElement bind(CalculationContext context);
}

class _VariableReference extends _StackElement {
  _VariableReference(this.name, this.context);

  @override
  num get value => context[name] ?? 0;

  @override
  set value(num val) => context[name] = val;

  @override
  _Opcode toOpcode() => _Opcode(_Kind.identifier)..value = name;

  @override
  _VariableReference bind(CalculationContext context) =>
      _VariableReference(name, context);

  final String name;
  final CalculationContext context;
}

class _Literal extends _StackElement {
  _Literal(this._value);

  @override
  num get value => _value;

  @override
  set value(num val) =>
      throw CalculationException("You can't set a value to a literal");

  @override
  _Opcode toOpcode() => _Opcode(_Kind.number)..value = _value;

  @override
  _Literal bind(CalculationContext context) => this;

  final num _value;
}

typedef void _PerformOperation(_Opcode op, CalculationContext n);
typedef _Opcode _ToOpcode(_Token token);

class _KindDefinition {
  _KindDefinition(
    this.kind,
    this.singleCharacter, [
    this.perform,
    _ToOpcode? toOpcode,
  ]) : _toOpcodeOverride = toOpcode;

  _Opcode toOpcode(_Token token) {
    if (_toOpcodeOverride != null) return _toOpcodeOverride!(token);
    return _Opcode(token.kind)..value = token.value;
  }

  final _Kind kind;
  final String? singleCharacter;
  final _PerformOperation? perform;
  final _ToOpcode? _toOpcodeOverride;
}

final List<_KindDefinition> _tokenDefinitions = List.unmodifiable([
  _KindDefinition(_Kind.add, "+", (_Opcode op, CalculationContext n) {
    n.push(_Literal(n.pop().value + n.pop().value));
  }),
  _KindDefinition(_Kind.subtract, "-", (_Opcode op, CalculationContext n) {
    n.push(_Literal(-n.pop().value + n.pop().value));
  }),
  _KindDefinition(_Kind.multiply, "*", (_Opcode op, CalculationContext n) {
    n.push(_Literal(n.pop().value * n.pop().value));
  }),
  _KindDefinition(_Kind.divide, "/", (_Opcode op, CalculationContext n) {
    final num a = n.pop().value;
    final num b = n.pop().value;
    n.push(_Literal(b / a));
  }),
  _KindDefinition(
    _Kind.number,
    null,
    (_Opcode op, CalculationContext n) {
      n.push(_Literal(op.value! as num));
    },
    (_Token token) => _Opcode(token.kind)..value = num.parse(token.value!),
  ),
  _KindDefinition(_Kind.identifier, null, (_Opcode op, CalculationContext n) {
    n.push(_VariableReference(op.value! as String, n));
  }),
  _KindDefinition(_Kind.assign, "=", (_Opcode op, CalculationContext n) {
    final num value = n.pop().value;
    final _VariableReference target = n.pop() as _VariableReference;
    target.value = value;
    n.push(_Literal(value));
  }),
  _KindDefinition(_Kind.openBracket, "("),
  _KindDefinition(_Kind.closeBracket, ")"),
]);
final Map<_Kind, _KindDefinition> _kindDefs = Map.unmodifiable(
  Map.fromEntries(_tokenDefinitions.map((def) => MapEntry(def.kind, def))),
);

final Map<String, _Kind> _singleCharacterTokens = Map.unmodifiable(
  Map.fromEntries(
    _kindDefs.entries.where((entry) => entry.value.singleCharacter != null).map(
          (entry) => MapEntry(entry.value.singleCharacter, entry.value.kind),
        ),
  ),
);

String kindToString(_Kind kind) {
  final String kindString = kind.toString();
  final int dot = kindString.indexOf('.');
  if (dot < 0) return kindString;
  return kindString.substring(dot + 1);
}

abstract class _Kindful {
  _Kind get kind;
}

class _Token implements _Kindful {
  _Token(this.kind);

  @override
  String toString() => "${kindToString(kind)}(${value ?? ''})";
  _Opcode toOpcode() => _kindDefs[kind]!.toOpcode(this);

  @override
  _Kind kind;

  String? value;
}

class _Opcode implements _Kindful {
  _Opcode(this.kind);

  @override
  String toString() =>
      "${kindToString(kind)}${value != null ? ' ' : ''}${value ?? ''}";
  void perform(CalculationContext context) =>
      _kindDefs[kind]!.perform!(this, context);

  @override
  _Kind kind;

  Object? value;
}

final Map<_Kind, RegExp> _patternTokens = Map.unmodifiable({
  _Kind.number: RegExp(r"(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?"),
  _Kind.identifier: RegExp(r"[_a-zA-Z][_a-zA-Z0-9]*"),
});

Iterable<_Token> _tokenize(String buffer) sync* {
  final int l = buffer.length;
  for (int i = 0; i < l; ++i) {
    if (buffer[i] == " ") continue;
    final _Kind? single = _singleCharacterTokens[buffer[i]];
    if (single == null) {
      bool found = false;
      for (final _Kind k in _patternTokens.keys) {
        final RegExp re = _patternTokens[k]!;
        if (buffer.startsWith(re, i)) {
          found = true;
          final String match = re.stringMatch(buffer.substring(i))!;
          yield _Token(k)..value = match;
          i += match.length - 1;
          break;
        }
      }
      if (!found) {
        throw CalculationParseException(
          "Found a strange character in the source at $i: ${buffer[i]}",
          buffer,
          i,
        );
      }
    } else {
      yield _Token(single)..kind;
    }
  }
}

int _valueExpression(List<_Opcode> ops, List<_Token> tokens, int cursor) {
  int currentCursor = cursor;
  final _Token current = tokens[currentCursor];
  if (current.kind == _Kind.openBracket) {
    currentCursor = _expression.expression(ops, tokens, currentCursor + 1);
    if (tokens[currentCursor].kind != _Kind.closeBracket) {
      throw CalculationParseException("Ouch, no closing bracket");
    }
    return currentCursor + 1;
  }
  if (current.kind == _Kind.identifier) {
    ops.add(tokens[currentCursor].toOpcode());
  } else {
    if (current.kind == _Kind.subtract) ++currentCursor;
    assert(tokens[currentCursor].kind == _Kind.number);
    ops.add(
      (tokens[currentCursor]
            ..value = "${current.kind == _Kind.subtract ? '-' : ''}"
                "${tokens[currentCursor].value}")
          .toOpcode(),
    );
  }
  return currentCursor + 1;
}

class _PrecedenceGroup {
  _PrecedenceGroup(Iterable<_Kind> kinds, [this.parent])
      : kinds = kinds.toSet();

  int halfExpression(List<_Opcode> ops, List<_Token> tokens, int cursor) {
    _Token? opToken;
    if (kinds.contains(tokens[cursor].kind)) {
      // E => E + T
      opToken = tokens[cursor];
    } else {
      // this is not an expression, E => T
      return cursor;
    }

    return expression(ops, tokens, cursor + 1, opToken);
  }

  int expression(
    List<_Opcode> ops,
    List<_Token> tokens,
    int cursor, [
    _Token? lastTokenOp,
  ]) {
    final int afterTerm = parent == null
        ? _valueExpression(ops, tokens, cursor)
        : parent!.expression(ops, tokens, cursor);
    if (lastTokenOp != null) ops.add(lastTokenOp.toOpcode());
    if (afterTerm < tokens.length) {
      return halfExpression(ops, tokens, afterTerm);
    }
    return afterTerm;
  }

  _PrecedenceGroup over(Iterable<_Kind> kinds) => _PrecedenceGroup(kinds, this);

  final _PrecedenceGroup? parent;
  final Set<_Kind> kinds;
}

_PrecedenceGroup _expression = _PrecedenceGroup([_Kind.multiply, _Kind.divide])
    .over([_Kind.add, _Kind.subtract]).over([_Kind.assign]);

int _parseTokens(List<_Opcode> ops, List<_Token> tokens, int cursor) {
  return _expression.expression(ops, tokens, cursor);
}

class Program {
  /// Creates a program by parsing a source expression.
  Program(String source) {
    _parseTokens(_ops, _tokenize(source).toList(growable: false), 0);
  }

  Program._fromOps(List<_Opcode> ops) : _ops = List.unmodifiable(ops);

  /// Executes the program in the given calculaton context.
  num execute([CalculationContext? context]) {
    context ??= CalculationContext();
    for (final _Opcode op in _ops) {
      op.perform(context);
    }
    return context.pop().value;
  }

  /// Returns an optimized version of the program if possible.
  /// Tries to calculate as much as it can in advance.
  Program optimize() {
    final _OptimizationContext context = _OptimizationContext();
    // new, optimized opcodes
    final List<_Opcode> newOps = [];
    // the bound to which we have already added the opcodes
    // we don't automatically add opcodes for contextfree calculations,
    // only when needed, but we need to save where we have to
    // build the stack when we do have to
    int stackBound = 0;
    // we save the stack from the last written opcode before the operation,
    // so if the operation taints the stack, we emit this, and emit the
    // opcode that tainted the stack
    List<_StackElement>? stackSave;
    for (final _Opcode op in _ops) {
      if (context.stackIsNotEmpty && context.topIsLiteral) {
        stackSave = context.stackSince(stackBound).toList(growable: false);
      } else {
        stackSave = null;
      }
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
      return Program._fromOps(
        [_Opcode(_Kind.number)..value = context.topValue],
      );
    }
    if (newOps.length < _ops.length) return Program._fromOps(newOps);
    // could not optimize
    return this;
  }

  int get numOpcodes => _ops.length;

  /// Provides a stirng representation of the program by listing
  /// the opcodes seperated by newlines.
  @override
  String toString() => _ops.join("\n");

  List<_Opcode> _ops = [];
}
