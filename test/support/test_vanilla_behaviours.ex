# Vanilla behaviour modules for testing DoubleDown.Facade.BehaviourIntrospection
# and DoubleDown.ContractFacade.Behaviour.

defmodule DoubleDown.Test.VanillaBehaviour do
  @moduledoc "Simple behaviour with annotated params."

  @callback get_item(id :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback list_items() :: [map()]
  @callback create_item(attrs :: map(), opts :: keyword()) :: {:ok, map()} | {:error, term()}
end

defmodule DoubleDown.Test.BareTypesBehaviour do
  @moduledoc "Behaviour with bare (unannotated) param types."

  @callback fetch(String.t(), keyword()) :: {:ok, term()} | :error
end

defmodule DoubleDown.Test.WhenClauseBehaviour do
  @moduledoc "Behaviour with when clause (bounded type variables)."

  @callback transform(input) :: output when input: term(), output: term()
end

defmodule DoubleDown.Test.MixedParamsBehaviour do
  @moduledoc "Behaviour mixing annotated and bare params."

  @callback mixed(name :: String.t(), integer(), opts :: keyword()) :: :ok | :error
end

defmodule DoubleDown.Test.ZeroArgBehaviour do
  @moduledoc "Behaviour with only zero-arg callbacks."

  @callback ping() :: :pong
  @callback health_check() :: {:ok, map()} | {:error, term()}
end

defmodule DoubleDown.Test.NotABehaviour do
  @moduledoc "A regular module with no @callback declarations."

  def hello, do: :world
end
