# Dynamic facades must be set up before ExUnit starts
DoubleDown.Dynamic.setup(DoubleDown.Test.DynamicTarget)

ExUnit.start()
{:ok, _} = DoubleDown.Testing.start()
