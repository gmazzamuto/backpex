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
        doc: """
        The create action used for new items. If not specified, the primary `:create` action will be used. Can be an
        atom or a tuple with action name, action arguments and action options, eg:
        `{:create, %{my_argument: "value"}, []}`. It can also be a function that takes the `assigns`.
        """,
        type: {:or, [:atom, {:tuple, [:atom, :map, :keyword_list]}, {:fun, 1}]},
        default: nil
      ],
      index_action: [
        doc: """
        The read action used for index views. If not specified, the primary `:read` action will be used. If a custom
        action is specified, that action needs to have offset pagination enabled (see
        [Ash Pagination](https://hexdocs.pm/ash/pagination.html)). Can be an atom or a tuple with action name and action
        arguments, eg: `{:read, %{my_argument: "value"}}`. It can also be a function that takes the `assigns`.
        """,
        type: {:or, [:atom, {:tuple, [:atom, :map, :keyword_list]}, {:fun, 1}]},
        default: nil
      ],
      show_action: [
        doc: """
        The read action used for show views. It is also used to load the initial data for edit views. If not specified,
        the primary `:read` action will be used. Can be an atom or a tuple with action name and action arguments, eg:
        `{:read, %{my_argument: "value"}}`. It can also be a function that takes the `assigns`.
        """,
        type: {:or, [:atom, {:tuple, [:atom, :map, :keyword_list]}, {:fun, 1}]},
        default: nil
      ],
      update_action: [
        doc: """
        The update action used for updating a resource on edit views. If not specified, the primary `:update` action
        will be used. Can be an atom or a function that takes the `assigns`. Can be an atom or a tuple with action name
        and action arguments, eg: `{:update, %{my_argument: "value"}}`. It can also be a function that takes the `assigns`.
        """,
        type: {:or, [:atom, {:fun, 1}]},
        default: nil
      ],
      destroy_action: [
        doc: """
        The destroy action used for deleting items. If not specified, the primary `:destroy` action will be used. Can be
        an atom or a tuple with action name and action arguments, eg: `{:destroy, %{my_argument: "value"}}`.
        """,
        type: {:or, [:atom, {:tuple, [:atom, :map, :keyword_list]}]},
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

    ## Validations

    > ### A note on validations {: .warning}
    >
    > If you have computationally expensive [validations](https://hexdocs.pm/ash/validations.html), keep in mind that
    > Backpex calls `Ash.can?/3` multiple times in the Index view to determine which actions the user is allowed to
    > perform and to update the UI accordingly. Unfortunately, calling `Ash.can?/3` causes the `Ash.Changeset` to be
    > validated, and this in turn causes your expensive validations to be run multiple times. This can result in a
    > noticeable delay in the loading of the Index view. If your validation is not needed for the authorization logic,
    > it can be skipped like this:
    > ```elixir
    > validate {MyExpensiveValidation, field: :my_field}, where: Backpex.NotAnAuthCheck
    > ```
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
    def get(primary_value, _fields, assigns, live_resource) do
      resource = live_resource.adapter_config(:resource)
      primary_key = live_resource.config(:primary_key)

      {action, action_args, action_opts} = get_ash_action(live_resource, :show, assigns)

      action_opts = Keyword.merge(get_actor_option(assigns), action_opts)

      resource
      |> Ash.Query.for_read(action, action_args, action_opts)
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
    def list_query(criteria, %{live_resource: live_resource} = assigns) do
      resource = live_resource.adapter_config(:resource)
      {action, action_args, action_options} = get_ash_action(live_resource, :index, assigns)

      action_options = Keyword.merge(get_actor_option(assigns), action_options)

      sort_options =
        case criteria[:order] do
          %{direction: direction, by: by} -> Keyword.new([{by, direction}])
          _default -> []
        end

      resource
      |> Ash.Query.for_read(action, action_args, action_options)
      |> Ash.Query.sort(sort_options)
      |> apply_search(criteria[:search], live_resource)
      |> apply_filters(criteria[:filters], Backpex.LiveResource.empty_filter_key(), assigns)
      |> apply_pagination(criteria[:pagination])
    end

    defp apply_pagination(query, nil), do: query

    defp apply_pagination(query, pagination_criteria) do
      %{size: limit, page: page} = pagination_criteria
      Ash.Query.page(query, limit: limit, offset: limit * (page - 1), count: true)
    end

    @spec get_ash_action(atom(), :create | :index | :show | :update | :destroy, any()) :: {atom(), map(), keyword()}
    @doc """
    Return the Ash [action](https://hexdocs.pm/ash/actions.html) (and arguments) to use, determined in the following order:
    1. the action specified in the `adapter_config`
    2. the corresponding primary action for the given Ash resource. `:index` and `:show` actions use the `read` action.
    """
    def get_ash_action(live_resource, action, assigns) when action in [:create, :index, :show, :update, :destroy] do
      resource = live_resource.adapter_config(:resource)
      action_key = String.to_existing_atom("#{action}_action")

      ash_action =
        case action do
          action when action in [:index, :show] -> :read
          action -> action
        end

      ash_action_and_args =
        case live_resource.adapter_config(action_key) do
          nil -> if(action = Resource.Info.primary_action(resource, ash_action), do: action.name)
          f when is_function(f, 1) -> f.(assigns)
          action when is_atom(action) -> action
        end

      case ash_action_and_args do
        # with empty arguments
        ash_action when is_atom(ash_action) -> {ash_action, %{}, []}
        ash_action_and_args -> ash_action_and_args
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

      {destroy_action, action_input, action_opts} =
        get_ash_action(live_resource, :destroy, "passing assigns is not supported for delete actions")

      result =
        live_resource.adapter_config(:resource)
        |> Ash.Query.filter(^Ash.Expr.ref(primary_key) in ^ids)
        |> Ash.bulk_destroy(destroy_action, action_input, Keyword.merge([return_records?: true], action_opts))

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
