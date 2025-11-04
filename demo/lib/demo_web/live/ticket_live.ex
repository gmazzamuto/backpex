defmodule DemoWeb.TicketLive do
  use Backpex.LiveResource,
    adapter: Backpex.Adapters.Ash,
    adapter_config: [
      resource: Demo.Helpdesk.Ticket
    ],
    layout: {DemoWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Ticket"

  @impl Backpex.LiveResource
  def plural_name, do: "Tickets"

  @impl Backpex.LiveResource
  def render_resource_slot(assigns, :index, :before_page_title) do
    ~H"""
    <Backpex.HTML.Layout.alert kind={:info} closable={false}>
      This resource uses the <strong>Ash adapter</strong>, which is currently in a very early alpha stage.
      Currently, only <strong>index</strong>, <strong>show</strong> and <strong>delete</strong> are functional in a
      very basic form. We are working on supporting more Backpex features in the future.
    </Backpex.HTML.Layout.alert>
    """
  end

  @impl Backpex.LiveResource
  def fields do
    [
      subject: %{
        module: Backpex.Fields.Text,
        label: "Subject",
        orderable: true,
        searchable: true
      },
      body: %{
        module: Backpex.Fields.Textarea,
        label: "Body",
        orderable: false,
        except: [:index]
      },
      status: %{
        module: Backpex.Fields.Select,
        label: "Status",
        orderable: true,
        options: Demo.Helpdesk.Ticket.status_options(),
        index_editable: true
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created at",
        orderable: true
      }
    ]
  end

  @impl Backpex.LiveResource
  def filters do
    [
      status: %{
        module: DemoWeb.Filters.TicketStatusBoolean,
        label: "Status"
      },
      inserted_at: %{
        module: DemoWeb.Filters.DateTimeRange,
        label: "Created at",
        presets: [
          %{
            label: "Last 7 Days",
            values: fn ->
              %{
                "start" => Date.add(Date.utc_today(), -7),
                "end" => Date.utc_today()
              }
            end
          },
          %{
            label: "Last 14 Days",
            values: fn ->
              %{
                "start" => Date.add(Date.utc_today(), -14),
                "end" => Date.utc_today()
              }
            end
          },
          %{
            label: "Last 30 Days",
            values: fn ->
              %{
                "start" => Date.add(Date.utc_today(), -30),
                "end" => Date.utc_today()
              }
            end
          }
        ]
      }
    ]
  end
end
