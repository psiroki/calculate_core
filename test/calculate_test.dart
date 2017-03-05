import "package:calculate_core/calculate_core.dart";
import "package:test/test.dart";

class Pair<A, B> {
  const Pair(this.first, this.second);

  final A first;
  final B second;
}

void main(List<String> args) {
  test("Very simple calculation", () {
    Program simple = new Program("2+2");
    expect(simple.execute(), equals(4));
  });

  test("Simple assignment", () {
    Program simple = new Program("pi=3.141592654");
    CalculationContext context = new CalculationContext();
    expect(simple.execute(context), equals(3.141592654));
    expect(context["pi"], equals(3.141592654));
  });

  test("Multiple assignments and simple calculations", () {
    CalculationContext context = new CalculationContext();
    List<Pair<Program, num>> pairs = [
      new Pair(new Program("a=3"), 3),
      new Pair(new Program("b=5"), 5),
      new Pair(new Program("a*b"), 15),
    ];
    for (Pair<Program, num> pair in pairs)
      expect(pair.first.execute(context), equals(pair.second));
    expect(context["a"], equals(3));
    expect(context["b"], equals(5));
  });

  test("Operator precedence", () {
    Program prec = new Program("-2+-3*7/(2+2*0.5-0.5)-5");
    expect(prec.execute(), equals(-15.4));
  });

  test("Simple optimization: no variables", () {
    Program prec = new Program("-2+-3*7/(2+2*0.5-0.5)-5");
    Program opt = prec.optimize();
    expect(opt.execute(), equals(-15.4), reason: "The result is correct");
    expect(prec.numOpcodes, greaterThan(1),
        reason:
            "The test is incorrect: originally there was more than one opcode");
    expect(opt.numOpcodes, equals(1),
        reason: "The final number of opcodes is not exactly one");
  });

  test("Simple optimization with tailing variables", () {
    Program prec = new Program("2+2+a+b");
    Program opt = prec.optimize();
    CalculationContext context = new CalculationContext();
    context["a"] = 5;
    context["b"] = 3;
    expect(opt.execute(context), equals(12), reason: "The result is incorrect");
    expect(opt.numOpcodes, lessThan(prec.numOpcodes),
        reason: "The number of opcodes has not decreased");
  });

  test("Tail optimization", () {
    Program prec = new Program("a+b+(2+2)");
    Program opt = prec.optimize();
    CalculationContext context = new CalculationContext();
    context["a"] = 5;
    context["b"] = 3;
    expect(opt.execute(context), equals(12), reason: "The result is incorrect");
    expect(opt.numOpcodes, lessThan(prec.numOpcodes),
        reason: "The number of opcodes has not decreased");
  });

  test("Complex optimization", () {
    String source = "7*2.5+a*b+(3+2+2*a-7*8)";
    Program prec = new Program(source);
    Program opt = prec.optimize();
    CalculationContext context = new CalculationContext();
    context["a"] = 5;
    context["b"] = 3;
    expect(opt.execute(context), equals(-8.5), reason: "The result is incorrect");
    expect(opt.numOpcodes, lessThan(prec.numOpcodes),
        reason: "The number of opcodes has not decreased");
  });
}
