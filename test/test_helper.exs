# Dynamic facades must be set up before ExUnit starts
DoubleDown.DynamicFacade.setup(DoubleDown.Test.DynamicTarget)

ExUnit.start()
{:ok, _} = DoubleDown.Testing.start()
