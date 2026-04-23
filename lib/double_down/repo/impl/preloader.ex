if Code.ensure_loaded?(Ecto) do
  defmodule DoubleDown.Repo.Impl.Preloader do
    @moduledoc false

    # In-memory preloader that uses Ecto schema reflection to resolve
    # associations from the InMemory store.
    #
    # Supports: has_many, has_one, belongs_to, many_to_many (when join
    # schema is in store), has_through (by chaining).

    alias DoubleDown.Repo.Impl.InMemoryShared

    @doc false
    @spec preload(term(), term(), InMemoryShared.store()) :: term()
    def preload(nil, _preloads, _store), do: nil

    def preload([], _preloads, _store), do: []

    def preload(structs, preloads, store) when is_list(structs) do
      Enum.map(structs, &preload(&1, preloads, store))
    end

    def preload(struct, preloads, store) when is_map(struct) do
      preloads
      |> normalize_preloads()
      |> Enum.reduce(struct, fn {field, sub_preloads}, acc ->
        schema = acc.__struct__
        assoc = schema.__schema__(:association, field)

        if assoc == nil do
          raise ArgumentError,
                "schema #{inspect(schema)} does not have association #{inspect(field)}"
        end

        loaded = resolve_assoc(assoc, acc, store)

        # Apply nested preloads
        loaded =
          case sub_preloads do
            [] -> loaded
            nested when is_list(loaded) -> Enum.map(loaded, &preload(&1, nested, store))
            nested when is_map(loaded) -> preload(loaded, nested, store)
            _nested -> loaded
          end

        Map.put(acc, field, loaded)
      end)
    end

    # -----------------------------------------------------------------
    # Association resolution
    # -----------------------------------------------------------------

    defp resolve_assoc(%Ecto.Association.Has{} = assoc, struct, store) do
      %{
        owner_key: owner_key,
        related_key: related_key,
        related: related,
        cardinality: cardinality,
        where: where_clauses
      } = assoc

      owner_val = Map.fetch!(struct, owner_key)
      records = InMemoryShared.records_for_schema(store, related)

      matching =
        records
        |> Enum.filter(&(Map.get(&1, related_key) == owner_val))
        |> apply_where_clauses(where_clauses)

      case cardinality do
        :many -> matching
        :one -> List.first(matching)
      end
    end

    defp resolve_assoc(%Ecto.Association.BelongsTo{} = assoc, struct, store) do
      %{owner_key: owner_key, related_key: related_key, related: related} = assoc

      fk_val = Map.get(struct, owner_key)

      if is_nil(fk_val) do
        nil
      else
        records = InMemoryShared.records_for_schema(store, related)
        Enum.find(records, &(Map.get(&1, related_key) == fk_val))
      end
    end

    defp resolve_assoc(%Ecto.Association.ManyToMany{} = assoc, struct, store) do
      %{
        owner_key: owner_key,
        related: related,
        join_keys: [{join_owner_key, _owner_key}, {join_related_key, related_key}],
        join_through: join_through,
        where: where_clauses
      } = assoc

      owner_val = Map.fetch!(struct, owner_key)

      # Get join records
      join_records =
        case join_through do
          mod when is_atom(mod) ->
            InMemoryShared.records_for_schema(store, mod)

          table when is_binary(table) ->
            # String table names not supported without a schema module
            []
        end

      # Find matching join records
      related_keys =
        join_records
        |> Enum.filter(&(Map.get(&1, join_owner_key) == owner_val))
        |> Enum.map(&Map.get(&1, join_related_key))

      # Look up related records
      related_records = InMemoryShared.records_for_schema(store, related)

      related_records
      |> Enum.filter(&(Map.get(&1, related_key) in related_keys))
      |> apply_where_clauses(where_clauses)
    end

    defp resolve_assoc(%Ecto.Association.HasThrough{} = assoc, struct, store) do
      %{through: through, cardinality: cardinality} = assoc

      # Walk the chain of associations
      result =
        Enum.reduce(through, [struct], fn assoc_name, current ->
          current
          |> List.wrap()
          |> Enum.reject(&is_nil/1)
          |> Enum.flat_map(fn item ->
            schema = item.__struct__
            step_assoc = schema.__schema__(:association, assoc_name)
            resolved = resolve_assoc(step_assoc, item, store)
            List.wrap(resolved)
          end)
        end)

      # Deduplicate by PK if the schema has one
      result = deduplicate(result)

      case cardinality do
        :many -> result
        :one -> List.first(result)
      end
    end

    # -----------------------------------------------------------------
    # Helpers
    # -----------------------------------------------------------------

    defp normalize_preloads(preloads) when is_atom(preloads), do: [{preloads, []}]

    defp normalize_preloads(preloads) when is_list(preloads) do
      Enum.flat_map(preloads, fn
        {field, sub} when is_atom(field) -> [{field, normalize_preloads(sub)}]
        field when is_atom(field) -> [{field, []}]
      end)
    end

    defp apply_where_clauses(records, nil), do: records
    defp apply_where_clauses(records, []), do: records

    defp apply_where_clauses(records, clauses) do
      Enum.filter(records, fn record ->
        Enum.all?(clauses, fn {field, value} ->
          Map.get(record, field) == value
        end)
      end)
    end

    defp deduplicate([]), do: []

    defp deduplicate([first | _] = records) do
      schema = first.__struct__

      if function_exported?(schema, :__schema__, 1) do
        case schema.__schema__(:primary_key) do
          [pk_field] ->
            records
            |> Enum.uniq_by(&Map.get(&1, pk_field))

          _ ->
            records
        end
      else
        records
      end
    end
  end
end
