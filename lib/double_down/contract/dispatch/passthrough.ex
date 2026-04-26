defmodule DoubleDown.Contract.Dispatch.Passthrough do
  @moduledoc """
  Sentinel value returned from expect responders to delegate to the
  fallback/fake instead of returning a result directly.

  Use `DoubleDown.Double.passthrough/0` to create this value rather
  than constructing the struct directly.

  When an expect responder returns this sentinel, the call is handled
  by the fallback (stateful fake, function fallback, or module fake)
  as if the expect had been registered with `:passthrough`. The expect
  is still consumed for `verify!` counting.

  This enables conditional passthrough — the responder can inspect
  the state and decide whether to handle the call or delegate:

      DoubleDown.Double.expect(:insert, fn [changeset], state ->
        if duplicate?(state, changeset) do
          {{:error, add_error(changeset, :email, "taken")}, state}
        else
          DoubleDown.Double.passthrough()
        end
      end)
  """

  @type t :: %__MODULE__{}
  defstruct []

  @doc "Create a new Passthrough sentinel."
  @spec new() :: t()
  def new, do: %__MODULE__{}
end
