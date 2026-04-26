defmodule DoubleDown.Double.Types do
  @moduledoc """
  Shared type definitions for per-operation functions in `DoubleDown.Double`.

  These types describe the function signatures accepted by `expect/4`,
  `stub/3`, and `fake/3` — the per-operation Double API.
  """

  @typedoc """
  A stateless expect responder: `fn [args] -> result end`.
  """
  @type stateless_expect :: ([term()] -> term())

  @typedoc """
  A stateful expect responder reading the fallback's state:
  `fn [args], state -> {result, new_state} end`.
  """
  @type stateful_expect :: ([term()], term() -> {term(), term()})

  @typedoc """
  A stateful expect responder with cross-contract state access:
  `fn [args], state, all_states -> {result, new_state} end`.
  """
  @type cross_contract_expect :: ([term()], term(), map() -> {term(), term()})

  @typedoc """
  Any expect responder (stateless, stateful, or cross-contract).
  """
  @type expect_fun :: stateless_expect() | stateful_expect() | cross_contract_expect()

  @typedoc """
  A per-operation stub function: `fn [args] -> result end`.
  Always 1-arity (stateless).
  """
  @type stub_fun :: ([term()] -> term())

  @typedoc """
  A per-operation fake function reading the fallback's state:
  `fn [args], state -> {result, new_state} end`.
  """
  @type stateful_fake :: ([term()], term() -> {term(), term()})

  @typedoc """
  A per-operation fake function with cross-contract state access:
  `fn [args], state, all_states -> {result, new_state} end`.
  """
  @type cross_contract_fake :: ([term()], term(), map() -> {term(), term()})

  @typedoc """
  Any per-operation fake function (stateful or cross-contract).
  """
  @type fake_fun :: stateful_fake() | cross_contract_fake()
end
