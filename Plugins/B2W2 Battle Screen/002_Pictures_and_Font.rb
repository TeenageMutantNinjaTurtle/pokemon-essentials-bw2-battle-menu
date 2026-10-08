#===============================================================================
# The pictures of Black 2 and White 2's lower screen, which tools/b2w2_pictures.py
# makes from the ROM, and the game's font.
#===============================================================================
module B2W2
  ART = "Graphics/Pictures/B2W2/"

  class << self
    # The battle's lower screen while a battle is on
    attr_accessor :lower
  end

  def self.art(name, folder = "Battle")
    @art ||= {}
    path = "#{ART}#{folder}/#{name}"
    @art[path] = Bitmap.new(path) if !@art[path] || @art[path].disposed?
    return @art[path]
  end

  # White 2's font 0. The sheets hold it in the four colour pairs of the text palette: 0 white, then the three
  # colours of running-out PP.
  module Font
    def self.glyphs
      if !@glyphs
        lines = File.readlines(ART + "Battle/font.txt")
        @cell = lines.shift.split.map(&:to_i)
        @glyphs = {}
        lines.each_with_index do |line, i|
          code, left, width, advance = line.split.map(&:to_i)
          @glyphs[code] = [i, left, width, advance]
        end
      end
      return @glyphs
    end

    def self.width(text)
      return text.each_char.sum { |char| (glyphs[char.ord] || glyphs[63])[3] }
    end

    # colours is one of the battle's colour pairs, or a sheet of the font in other colours
    def self.draw(bitmap, x, y, text, colours = 0, centred = false)
      x -= width(text) / 2 if centred
      sheet = colours.is_a?(Bitmap) ? colours : B2W2.art("font_#{colours}")
      text.each_char do |char|
        index, left, width, advance = glyphs[char.ord] || glyphs[63]
        bitmap.blt((x + left) * 2, y * 2, sheet,
                   Rect.new(index % 32 * @cell[0] * 2, index / 32 * @cell[1] * 2, width * 2, @cell[1] * 2))
        x += advance
      end
    end
  end
end
