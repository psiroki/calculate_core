import "package:calculator/calculator_core.dart";

void main(List<String> args) {
  CalculationContext context = new CalculationContext();
  Program pie = new Program("pi=3.141592654");
  print(pie.execute(context));
  Program randomProgram = new Program("-2+-3*pi/(2+2)-5");
  print(randomProgram);
  print(randomProgram.execute(context));
}
