if Code.ensure_loaded?(Ash) do
  defmodule Backpex.Adapters.Ash do
    @config_schema [
      resource: [
        doc: "The `Ash.Resource` that will be used to perform CRUD operations.",
        type: :atom,
        required: true
      ],
      assigns_actor_path: [
        doc: """
          The path in the `assigns` to retrieve the actor used for Ash actions. To set the path for the whole Backpex,
          set the `:actor_assigns_path` option in your `config.exs`. For example:
        ```elixir
        config :backpex, assigns_actor_path: [:current_user]
        ```
        or
        ```elixir
        config :backpex, assigns_actor_path: [:current_scope, :user]
        ```
        """,
        type: {:or, [:atom, {:fun, 1}]},
        default: nil
      ],
      create_action: [
        doc: "The create action used for new items. If not specified, the primary action will be used.",
        type: {:or, [:atom, {:fun, 1}]},
        default: nil
      ],
      read_action: [
        doc: """
        The read action used for indexing. If not specified, the primary action will be used. If a custom action is
        specified, that action needs to have offset pagination enabled (see [Ash Pagination](https://hexdocs.pm/ash/pagination.html)).
        """,
        type: {:or, [:atom, {:fun, 1}]},
        default: nil
      ],
      update_action: [
        doc: "The update action used for editing. If not specified, the primary action will be used.",
        type: {:or, [:atom, {:fun, 1}]},
        default: nil
      ],
      destroy_action: [
        doc: "The destroy action used for deleting items. If not specified, the primary action will be used.",
        type: {:or, [:atom, {:fun, 1}]},
        default: nil
      ]
    ]

    @moduledoc """
    The `Backpex.Adapter` to connect your `Backpex.LiveResource` to an `Ash.Resource`.

    > ### Work in progress {: .error}
    >
    > The `Backpex.Adapters.Ash` is currently not usable! It can barely list and show items. We will work on this as we continue to implement  the `Backpex.Adapter` pattern throughout the codebase.

    ## `adapter_config`

    #{NimbleOptions.docs(@config_schema)}

    ## Search & filters
    Search and filters work on attributes marked as [`public?`](https://hexdocs.pm/ash/dsl-ash-resource.html#attributes-attribute-public?).
    """

    use Backpex.Adapter, config_schema: @config_schema
    import Ash.Expr
    alias Ash.Resource
    require Logger
    require Ash.Query

    @doc """
    Gets a database record with the given primary key value.

    Returns `nil` if no result was found.
    """
    @impl Backpex.Adapter
    def get(primary_value, _fields, _assigns, live_resource) do
      resource = live_resource.adapter_config(:resource)
      primary_key = live_resource.config(:primary_key)

      resource
      |> Ash.Query.filter(^Ash.Expr.ref(primary_key) == ^primary_value)
      |> Ash.read_one()
    end

    @doc """
    Returns a list of items by given criteria.
    """
    @impl Backpex.Adapter
    def list(criteria, _fields, assigns, _live_resource) do
      list_query(criteria, assigns) |> Ash.read()
    end

    @doc """
    Returns the number of items matching the given criteria.
    """
    @impl Backpex.Adapter
    def count(criteria, _fields, assigns, _live_resource) do
      list_query(criteria, assigns) |> Ash.count()
    end

    # Returns the main database query for selecting a list of items by given criteria.
    defp list_query(criteria, %{live_resource: live_resource} = assigns) do
      %{size: limit, page: page} = criteria[:pagination]

      resource = live_resource.adapter_config(:resource)
      action = get_ash_primary_action(live_resource, :read, assigns)

      read_options = get_actor_option(assigns)

      sort_options =
        case criteria[:order] do
          %{direction: direction, by: by} -> Keyword.new([{by, direction}])
          _default -> []
        end

      resource
      |> Ash.Query.for_read(action, %{}, read_options)
      |> Ash.Query.sort(sort_options)
      |> apply_search(criteria[:search], live_resource)
      |> apply_filters(criteria[:filters], Backpex.LiveResource.empty_filter_key(), assigns)
      |> Ash.Query.page(limit: limit, offset: limit * (page - 1), count: true)
    end

    def get_ash_primary_action(live_resource, action, assigns) when action in [:create, :read, :update, :destroy] do
      resource = live_resource.adapter_config(:resource)
      action_key = String.to_existing_atom("#{action}_action")

      case live_resource.adapter_config(action_key) do
        nil -> if(action = Resource.Info.primary_action(resource, action), do: action.name)
        f when is_function(f, 1) -> f.(assigns)
        action when is_atom(action) -> action
      end
    end

    def get_actor_option(%{live_resource: live_resource} = assigns) do
      path =
        case live_resource.adapter_config(:assigns_actor_path) do
          nil -> Application.get_env(:backpex, :assigns_actor_path)
          f when is_function(f) -> f.(assigns)
          path -> path
        end

      actor =
        case path do
          nil ->
            nil

          path ->
            actor = get_in(assigns, path)

            if is_nil(actor) do
              raise "The actor at path `#{inspect(path)}` is nil."
            end

            actor
        end

      [actor: actor]
    end

    defp apply_search(query, {"", _searchable_fields}, _live_resource), do: query

    defp apply_search(query, {search_string, searchable_fields}, live_resource) do
      case live_resource.config(:full_text_search) do
        nil ->
          ilike_q = "%#{search_string}%"
          resource = live_resource.adapter_config(:resource)

          Enum.each(searchable_fields, fn {field, _v} -> raise_if_not_public(resource, field) end)

          Ash.Query.filter_input(resource,
            or: Enum.map(searchable_fields, fn {k, _v} -> Keyword.new([{k, [ilike: ilike_q]}]) end)
          )

        ts_vector_column ->
          Ash.Query.filter(
            query,
            expr(
              fragment(
                "? @@ websearch_to_tsquery(?)",
                ^ref(ts_vector_column),
                ^search_string
              )
            )
          )
      end
    end

    defp raise_if_not_public(resource, field) do
      if not Resource.Info.attribute(resource, field).public? do
        raise "Attribute #{inspect(field)} must be set as public for search to work."
      end
    end

    def apply_filters(query, filters, empty_filter_key, assigns) do
      Enum.reduce(filters, query, fn
        %{field: ^empty_filter_key} = _filter, acc ->
          acc

        %{field: field, value: value, filter_config: filter_config} = _filter, acc ->
          filter_config.module.query(acc, field, value, assigns)
      end)
    end

    @doc """
    Deletes multiple items.
    """
    @impl Backpex.Adapter
    def delete_all(items, live_resource) do
      primary_key = live_resource.config(:primary_key)
      ids = Enum.map(items, &Map.fetch!(&1, primary_key))

      destroy_action = get_ash_primary_action(live_resource, :destroy, "passing_assigns_not_supported")

      result =
        live_resource.adapter_config(:resource)
        |> Ash.Query.filter(^Ash.Expr.ref(primary_key) in ^ids)
        |> Ash.bulk_destroy(destroy_action, %{}, return_records?: true)

      {:ok, result.records}
    end

    @doc """
    Inserts given item.
    """
    @impl Backpex.Adapter
    def insert(_item, _live_resource) do
      raise "not implemented yet"
    end

    @doc """
    Updates given item.
    """
    @impl Backpex.Adapter
    def update(_item, _live_resource) do
      raise "not implemented yet"
    end

    @doc """
    Updates given items.
    """
    @impl Backpex.Adapter
    def update_all(_items, _updates, _live_resource) do
      raise "not implemented yet"
    end

    @doc """
    Applies a change to a given item.
    """
    @impl Backpex.Adapter
    def change(_item, _attrs, _fields, _assigns, _live_resource, _opts) do
      raise "not implemented yet"
    end
  end
end
