import "package:calculate_core/calculate_core.dart";
import "package:test/test.dart";

class Pair<A, B> {
  const Pair(this.first, this.second);

  final A first;
  final B second;
}

void main() {
  test("Very simple calculation", () {
    final Program simple = Program("2+2");
    expect(simple.execute(), equals(4));
  });

  test("Simple assignment", () {
    final Program simple = Program("pi=3.141592654");
    final CalculationContext context = CalculationContext();
    expect(simple.execute(context), equals(3.141592654));
    expect(context["pi"], equals(3.141592654));
  });

  test("Multiple assignments and simple calculations", () {
    final CalculationContext context = CalculationContext();
    final List<Pair<Program, num>> pairs = [
      Pair(Program("a=3"), 3),
      Pair(Program("b=5"), 5),
      Pair(Program("a*b"), 15),
    ];
    for (final Pair<Program, num> pair in pairs) {
      expect(pair.first.execute(context), equals(pair.second));
    }
    expect(context["a"], equals(3));
    expect(context["b"], equals(5));
  });

  test("Operator precedence", () {
    final Program prec = Program("-2+-3*7/(2+2*0.5-0.5)-5");
    expect(prec.execute(), equals(-15.4));
  });

  test("Simple optimization: no variables", () {
    final Program prec = Program("-2+-3*7/(2+2*0.5-0.5)-5");
    final Program opt = prec.optimize();
    expect(opt.execute(), equals(-15.4), reason: "The result is correct");
    expect(
      prec.numOpcodes,
      greaterThan(1),
      reason:
          "The test is incorrect: originally there was more than one opcode",
    );
    expect(
      opt.numOpcodes,
      equals(1),
      reason: "The final number of opcodes is not exactly one",
    );
  });

  test("Simple optimization with tailing variables", () {
    final Program prec = Program("2+2+a+b");
    final Program opt = prec.optimize();
    final CalculationContext context = CalculationContext();
    context["a"] = 5;
    context["b"] = 3;
    expect(opt.execute(context), equals(12), reason: "The result is incorrect");
    expect(
      opt.numOpcodes,
      lessThan(prec.numOpcodes),
      reason: "The number of opcodes has not decreased",
    );
  });

  test("Tail optimization", () {
    final Program prec = Program("a+b+(2+2)");
    final Program opt = prec.optimize();
    final CalculationContext context = CalculationContext();
    context["a"] = 5;
    context["b"] = 3;
    expect(opt.execute(context), equals(12), reason: "The result is incorrect");
    expect(
      opt.numOpcodes,
      lessThan(prec.numOpcodes),
      reason: "The number of opcodes has not decreased",
    );
  });

  test("Complex optimization", () {
    const String source = "7*2.5+a*b+(3+2+2*a-7*8)";
    final Program prec = Program(source);
    final Program opt = prec.optimize();
    final CalculationContext context = CalculationContext();
    context["a"] = 5;
    context["b"] = 3;
    expect(
      opt.execute(context),
      equals(-8.5),
      reason: "The result is incorrect",
    );
    expect(
      opt.numOpcodes,
      lessThan(prec.numOpcodes),
      reason: "The number of opcodes has not decreased",
    );
  });
}
