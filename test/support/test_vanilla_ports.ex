# BehaviourFacade facades and implementations for vanilla behaviour test modules.
# These are in a separate file from the behaviours so that the behaviours
# are fully compiled before the facades try to read their @callback specs.

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
