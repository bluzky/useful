# Test enum without Gettext
defmodule SimpleStatus do
  use DefEnum

  enum do
    value(:active, "active")
    value(:inactive, "inactive")
    value(:pending, "pending")
  end
end

# Test enum with Gettext integration
defmodule UserStatus do
  use DefEnum,
    gettext_module: TestGettext,
    gettext_domain: "enums"

  enum do
    value(:active, "active")
    value(:inactive, "inactive")
    value(:pending, "pending", label: "status.waiting")
  end
end

defmodule CustomDomainEnum do
  use DefEnum,
    gettext_module: TestGettext,
    gettext_domain: "custom"

  enum do
    value(:test, "test")
  end
end

# Test enum as separate module
defmodule WrapperForExternalStatus do
  use DefEnum

  enum module: ExternalStatus do
    value(:online, "online")
    value(:offline, "offline")
  end
end