require "jasper_helpers"
include JasperHelpers
module CaptchaHelper
  TRUTHY = %w(1 true yes on)

  # Captcha is on in production and off everywhere else, so development doesn't
  # shell out to ImageMagick on every form render. RATMACHINE_CAPTCHA_ENABLED
  # overrides that in either direction.
  def self.enabled?
    if setting = ENV["RATMACHINE_CAPTCHA_ENABLED"]?
      TRUTHY.includes?(setting.downcase.strip)
    else
      ENV["AMBER_ENV"]? == "production"
    end
  end

  def self.captcha_form()
    return "" unless enabled?

    new_captcha = Captcha.generate()
    content(element_name: :div, options: {class: "captcha_form"}.to_h) do
      content(element_name: :img, content: "", options: {src: "/dist/images/captcha/#{new_captcha.id.to_s}.png", alt: "captcha"}.to_h) + "<br/>" +
      hidden_field(:captcha_id, value: new_captcha.id) + "<br/>" +
      text_field(:captcha_value, placeholder: "captcha", autocomplete: "off") + "<br/>"
    end
  end
end
