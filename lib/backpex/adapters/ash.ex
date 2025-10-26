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
        type: {:list, :atom}
      ],
      read_action: [
        doc: """
        The read action used for indexing. If not specified, the primary action will be used. If a custom action is
        specified, that action needs to have offset pagination enabled (see [Ash Pagination](https://hexdocs.pm/ash/pagination.html)).
        """,
        type: :atom,
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
    """

    use Backpex.Adapter, config_schema: @config_schema
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
      action = live_resource.adapter_config(:read_action) || Resource.Info.primary_action(resource, :read).name

      read_options = get_actor_option(assigns)

      sort_options =
        case criteria[:order] do
          %{direction: direction, by: by} -> Keyword.new([{by, direction}])
          _default -> []
        end

      resource
      |> Ash.Query.for_read(action, %{}, read_options)
      |> Ash.Query.sort(sort_options)
      |> Ash.Query.page(limit: limit, offset: limit * (page - 1), count: true)
    end

    defp get_actor_option(%{live_resource: live_resource} = assigns) do
      path = live_resource.adapter_config(:assigns_actor_path) || Application.get_env(:backpex, :assigns_actor_path)

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

    @doc """
    Deletes multiple items.
    """
    @impl Backpex.Adapter
    def delete_all(items, live_resource) do
      primary_key = live_resource.config(:primary_key)
      ids = Enum.map(items, &Map.fetch!(&1, primary_key))

      result =
        live_resource.adapter_config(:resource)
        |> Ash.Query.filter(^Ash.Expr.ref(primary_key) in ^ids)
        |> Ash.bulk_destroy(:destroy, %{}, return_records?: true)

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
