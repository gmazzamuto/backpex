defmodule Demo.AshFactory do
  @moduledoc false
  use Smokestack

  alias Demo.Helpdesk.Ticket

  factory Ticket do
    attribute :subject, &Faker.Lorem.sentence/0
    attribute :body, &Faker.Lorem.paragraph/0
    attribute :status, choose(Ticket.status_options())
    attribute :contact_details, &contact_details_factory/0
  end

  def contact_details_factory do
    for i <- 0..Enum.random(0..3), i > 0 do
      %Demo.Helpdesk.ContactDetails{
        name: Faker.Person.En.name(),
        phone: Faker.Phone.EnUs.phone()
      }
    end
  end
end
