if Code.ensure_loaded?(Ecto) do
  defmodule DoubleDown.Repo.Impl.EctoParity do
    @moduledoc false

    # Functions that make the in-memory Repo fakes behave more like
    # real Ecto.Repo by inspecting Ecto schema metadata.
    #
    # Kept separate from InMemoryShared (which handles store mechanics)
    # so schema-introspection concerns are isolated and reusable.

    # -------------------------------------------------------------------
    # FK backfill
    # -------------------------------------------------------------------

    @doc false
    @spec backfill_foreign_keys(struct()) :: struct()
    def backfill_foreign_keys(%{__struct__: schema} = record) do
      if function_exported?(schema, :__schema__, 1) do
        schema.__schema__(:associations)
        |> Enum.reduce(record, fn assoc_name, acc ->
          case schema.__schema__(:association, assoc_name) do
            %Ecto.Association.BelongsTo{
              field: field,
              owner_key: fk_field,
              related_key: pk_field
            } ->
              backfill_belongs_to(acc, field, fk_field, pk_field)

            _other ->
              acc
          end
        end)
      else
        record
      end
    end

    defp backfill_belongs_to(record, assoc_field, fk_field, pk_field) do
      assoc_value = Map.get(record, assoc_field)
      fk_value = Map.get(record, fk_field)

      case {assoc_value, fk_value} do
        {%{__struct__: _} = parent, nil} ->
          # Association is loaded but FK is nil — copy parent's PK
          Map.put(record, fk_field, Map.get(parent, pk_field))

        _ ->
          # FK already set, or association not loaded — leave as-is
          record
      end
    end

    # -------------------------------------------------------------------
    # Association reset
    # -------------------------------------------------------------------

    @doc false
    @spec reset_associations(struct()) :: struct()
    def reset_associations(%{__struct__: schema} = record) do
      if function_exported?(schema, :__schema__, 1) do
        schema.__schema__(:associations)
        |> Enum.reduce(record, fn assoc_name, acc ->
          assoc = schema.__schema__(:association, assoc_name)

          Map.put(acc, assoc.field, %Ecto.Association.NotLoaded{
            __field__: assoc.field,
            __owner__: schema,
            __cardinality__: assoc.cardinality
          })
        end)
      else
        record
      end
    end
  end
end
