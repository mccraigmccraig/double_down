# BehaviourFacade facades and implementations for vanilla behaviour test modules.
#
# DoubleDown.BehaviourFacade uses Code.Typespec.fetch_callbacks/1 which needs
# the behaviour's .beam file on disk. During mix compile, all files in the same
# elixirc_paths are compiled in a single batch — .beam files aren't written
# until the batch finishes. To work around this, we explicitly compile the
# behaviour definitions here and write their .beam files before defining
# the facades that depend on them.
#
# In a real application this isn't an issue — the behaviour module would
# be in lib/ (or a dependency) and compiled in a prior batch.

DoubleDown.Facade.CompileHelper.ensure_compiled!("test/support/test_vanilla_behaviours.ex")

# -- Implementation for VanillaBehaviour --

defmodule DoubleDown.Test.VanillaBehaviour.Impl do
  @behaviour DoubleDown.Test.VanillaBehaviour

  @impl true
  def get_item(id), do: {:ok, %{id: id}}

  @impl true
  def list_items, do: [%{id: "1"}, %{id: "2"}]

  @impl true
  def create_item(attrs, _opts), do: {:ok, attrs}
end

# -- Facades --

defmodule DoubleDown.Test.VanillaBehaviour.Port do
  use DoubleDown.BehaviourFacade,
    behaviour: DoubleDown.Test.VanillaBehaviour,
    otp_app: :double_down
end

defmodule DoubleDown.Test.BareTypesBehaviour.Port do
  use DoubleDown.BehaviourFacade,
    behaviour: DoubleDown.Test.BareTypesBehaviour,
    otp_app: :double_down
end

defmodule DoubleDown.Test.WhenClauseBehaviour.Port do
  use DoubleDown.BehaviourFacade,
    behaviour: DoubleDown.Test.WhenClauseBehaviour,
    otp_app: :double_down
end

defmodule DoubleDown.Test.MixedParamsBehaviour.Port do
  use DoubleDown.BehaviourFacade,
    behaviour: DoubleDown.Test.MixedParamsBehaviour,
    otp_app: :double_down
end

defmodule DoubleDown.Test.ZeroArgBehaviour.Port do
  use DoubleDown.BehaviourFacade,
    behaviour: DoubleDown.Test.ZeroArgBehaviour,
    otp_app: :double_down
end
