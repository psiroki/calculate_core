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

class CalculationContext {
  _StackElement pop() => _stack.removeLast();
  void push(_StackElement newElement) {
    _stack.add(newElement.bind(this));
  }

  final Map<String, num> registers = {};
  final List<_StackElement> _stack = [];
}

abstract class _StackElement {
  num get value;
  void set value(num val);

  _StackElement bind(CalculationContext context);
}

class _VariableReference extends _StackElement {
  _VariableReference(this.name, [this.context]);

  num get value => context.registers[name] ?? 0;
  void set value(num val) {
    context.registers[name] = val;
  }

  _VariableReference bind(CalculationContext context) => new _VariableReference(name, context);

  final String name;
  final CalculationContext context;
}

typedef void _PerformOperation(_Token token, CalculationContext n);

class _TokenDefinition {
  _TokenDefinition(this.kind, this.singleCharacter, [this.perform]);

  final _Kind kind;
  final String singleCharacter;
  final _PerformOperation perform;
}

class _Literal extends _StackElement {
  _Literal(this._value);

  num get value => _value;

  void set value(num val) {
    throw "You can't set a value to a literal";
  }

  _Literal bind(CalculationContext context) => this;

  final num _value;
}

final List<_TokenDefinition> _tokenDefinitions = new List.unmodifiable([
  new _TokenDefinition(_Kind.add, "+", (_Token token, CalculationContext n) {
    n.push(new _Literal(n.pop().value + n.pop().value));
  }),
  new _TokenDefinition(_Kind.subtract, "-", (_Token token, CalculationContext n) {
    n.push(new _Literal(-n.pop().value + n.pop().value));
  }),
  new _TokenDefinition(_Kind.multiply, "*", (_Token token, CalculationContext n) {
    n.push(new _Literal(n.pop().value * n.pop().value));
  }),
  new _TokenDefinition(_Kind.divide, "/", (_Token token, CalculationContext n) {
    num a = n.pop().value, b = n.pop().value;
    n.push(new _Literal(b / a));
  }),
  new _TokenDefinition(_Kind.number, null, (_Token token, CalculationContext n) {
    n.push(new _Literal(num.parse(token.value)));
  }),
  new _TokenDefinition(_Kind.identifier, null,
      (_Token token, CalculationContext n) {
    n.push(new _VariableReference(token.value));
  }),
  new _TokenDefinition(_Kind.assign, "=", (_Token token, CalculationContext n) {
    num value = n.pop().value;
    _VariableReference target = n.pop() as _VariableReference;
    target.value = value;
    n.push(new _Literal(value));
  }),
  new _TokenDefinition(_Kind.openBracket, "("),
  new _TokenDefinition(_Kind.closeBracket, ")"),
]);
final Map<_Kind, _TokenDefinition> _tokenDefs = new Map.unmodifiable(
    new Map.fromIterable(_tokenDefinitions, key: (t) => t.kind));

final Map<String, _Kind> _singleCharacterTokens = new Map.unmodifiable(
    new Map.fromIterable(
        _tokenDefs.keys.where((k) => _tokenDefs[k].singleCharacter != null),
        key: (k) => _tokenDefs[k].singleCharacter));

class _Token {
  String toString() => "$kind(${value??''})";
  void perform(CalculationContext context) =>
    _tokenDefs[kind].perform(this, context);
  _Kind kind;
  String value;
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

int _valueExpression(List<_Token> ops, List<_Token> tokens, int cursor) {
  _Token current = tokens[cursor];
  if (current.kind == _Kind.openBracket) {
    cursor = _expression.expression(ops, tokens, cursor + 1);
    if (tokens[cursor].kind != _Kind.closeBracket)
      throw "Ouch, no closing bracket";
    return cursor + 1;
  }
  if (current.kind == _Kind.identifier) {
    ops.add(tokens[cursor]);
  } else {
    if (current.kind == _Kind.subtract) ++cursor;
    assert(tokens[cursor].kind == _Kind.number);
    ops.add(tokens[cursor]
      ..value = "${current.kind == _Kind.subtract ? '-' : ''}"
          "${tokens[cursor].value}");
  }
  return cursor + 1;
}

class _PrecedenceGroup {
  _PrecedenceGroup(Iterable<_Kind> kinds, [this.parent]) : this.kinds = kinds.toSet();

  int halfExpression(List<_Token> ops, List<_Token> tokens, int cursor) {
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

  int expression(List<_Token> ops, List<_Token> tokens, int cursor, [_Token lastTokenOp]) {
    int afterTerm = parent == null
        ? _valueExpression(ops, tokens, cursor)
        : parent.expression(ops, tokens, cursor);
    if (lastTokenOp != null) ops.add(lastTokenOp);
    if (afterTerm < tokens.length) return halfExpression(ops, tokens, afterTerm);
    return afterTerm;
  }

  _PrecedenceGroup over(Iterable<_Kind> kinds) => new _PrecedenceGroup(kinds, this);

  final _PrecedenceGroup parent;
  final Set<_Kind> kinds;
}

_PrecedenceGroup _expression = new _PrecedenceGroup([_Kind.multiply, _Kind.divide])
    .over([_Kind.add, _Kind.subtract])
    .over([_Kind.assign]);

int _parseTokens(List<_Token> ops, List<_Token> tokens, int cursor) {
  return _expression.expression(ops, tokens, cursor);
}

class Program {
  Program(String line) {
    _parseTokens(_ops, _tokenize(line).toList(growable: false), 0);
  }

  num execute([CalculationContext context]) {
    if (context == null)
      context = new CalculationContext();
    for (_Token op in _ops) {
      op.perform(context);
    }
    return context.pop().value;
  }

  String toString() => _ops.join("\n");

  List<_Token> _ops = [];
}
