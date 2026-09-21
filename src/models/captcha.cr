class Captcha < Granite::Base
  connection pg
  table captchas

  column id : Int64, primary: true
  column value : String
  timestamps

  def self.generate_captcha_string(length)
    string = ""
    length.times do
      string += ('a'.ord+Random.rand(26)).chr
    end
    string
  end

  def self.generate()
    destroy_old
    new_captcha = Captcha.create(value: generate_captcha_string(6))

    # -swirl rather than -implode: on a transparent canvas implode fills
    # everything outside its circle from the background, which inverts the
    # alpha and leaves the glyphs as holes punched in an opaque blob. -swirl
    # distorts just as well without touching transparency.
    pointsize = 32 + Random.rand(16)
    amplitude = 2 + Random.rand(4)          # -wave 0x0 is a no-op; 0 wavelength is worse
    wavelength = 30 + Random.rand(40)
    swirl = (Random.rand(2) == 0 ? -1 : 1) * (15 + Random.rand(25))

    Process.run("sh",["-c","convert -background transparent -fill black -font DejaVu-Sans -pointsize #{pointsize} -size 192x64 -gravity Center label:#{new_captcha.value} -wave #{amplitude}x#{wavelength} -swirl #{swirl} png:- 2>&1 > public/dist/images/captcha/#{new_captcha.id}.png"])
    new_captcha
  end

  def delete()
    begin
      File.delete("public/dist/images/captcha/#{id}.png")
    rescue
    end
    destroy()
  end

  def self.is_valid?(id, value, destroy = true)
    destroy_old
    found_captcha = Captcha.find(id)
    return false if found_captcha.nil?
    found_captcha_value = found_captcha.value
    found_captcha.delete() if destroy    
    found_captcha_value == value
  end
  
  def self.destroy_old()
    Captcha.where(:created_at, :lt, Time.utc - 5.minutes).each do |captcha|
      captcha.delete()
    end
  end
end
