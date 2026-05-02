# Start the DoubleDown ownership server before ExUnit
{:ok, _} = DoubleDown.Testing.start()

# Dynamic facades must be set up before ExUnit starts
DoubleDown.DynamicFacade.setup(DoubleDown.Test.DynamicTarget)
DoubleDown.DynamicFacade.setup(DoubleDown.Test.DynamicBehaviourTarget)
DoubleDown.DynamicFacade.setup(DoubleDown.Test.DynamicMacroTarget)
DoubleDown.DynamicFacade.setup(DoubleDown.Test.DynamicStructTarget)

# Start ExMachina's sequence server for factory tests
{:ok, _} = Application.ensure_all_started(:ex_machina)

ExUnit.start()
