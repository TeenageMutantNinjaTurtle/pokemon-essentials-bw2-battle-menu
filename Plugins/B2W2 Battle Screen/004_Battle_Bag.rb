#===============================================================================
# The bag in battle as it is in Black 2 and White 2: four pockets, the items of
# a pocket six to a page, and one item with its description and USE. Layout,
# tables and frame counts are White 2's. Positions are in DS pixels and drawn at
# twice the size.
#===============================================================================
module B2W2
  class BattleBag
    POCKET_NAMES = [["HP/PP", "RESTORE"], ["STATUS", "RESTORE"], ["POKÉ BALLS"], ["BATTLE ITEMS"]]
    # What White 2 keeps in the status pocket. Other items used on a Pokémon go to HP/PP, Poké Balls to their
    # own pocket, everything else to battle items. Full Restore is in both of the first two.
    STATUS = [:ANTIDOTE, :BURNHEAL, :ICEHEAL, :AWAKENING, :PARALYZEHEAL, :PARLYZHEAL, :FULLHEAL, :REVIVE,
              :MAXREVIVE, :HEALPOWDER, :REVIVALHERB, :LAVACOOKIE, :OLDGATEAU, :CASTELIACONE, :CHERIBERRY,
              :CHESTOBERRY, :PECHABERRY, :RAWSTBERRY, :ASPEARBERRY, :PERSIMBERRY, :LUMBERRY]
    # Per page, each button: where it answers to a touch, the middle and size of the key cursor on it, and where
    # Up, Down, Left and Right lead. A negative entry is the button the cursor came from, or that one.
    BUTTONS = [
      [[[0, 8, 128, 64], [64, 42, 132, 60], [0, 1, 0, 2]],
       [[0, 80, 128, 64], [64, 114, 132, 60], [0, 4, 1, 3]],
       [[128, 8, 128, 64], [192, 42, 132, 60], [2, 3, 0, 2]],
       [[128, 80, 128, 64], [192, 114, 132, 60], [2, 5, 1, 3]],
       [[8, 152, 200, 40], [108, 176, 204, 40], [1, 4, 4, 5]],
       [[216, 152, 40, 40], [236, 174, 40, 40], [-3, 5, 4, 5]]],
      [[[0, 8, 128, 48], [64, 32, 132, 54], [0, 2, 0, 1]],
       [[128, 8, 128, 48], [192, 32, 132, 54], [1, 3, 0, 1]],
       [[0, 56, 128, 48], [64, 80, 132, 54], [0, 4, 2, 3]],
       [[128, 56, 128, 48], [192, 80, 132, 54], [1, 5, 2, 3]],
       [[0, 104, 128, 48], [64, 128, 132, 54], [2, 6, 4, 5]],
       [[128, 104, 128, 48], [192, 128, 132, 54], [3, 6, 4, 5]],
       [[216, 152, 40, 40], [236, 174, 40, 40], [-5, 6, 6, 6]],
       [[0, 152, 40, 40]],     # previous page, by touch only
       [[40, 152, 40, 40]]],   # next page
      [[[8, 152, 200, 40], [108, 176, 204, 40], [0, 0, 0, 1]],
       [[216, 152, 40, 40], [236, 174, 40, 40], [1, 1, 0, 1]]]
    ]
    BAR, BACK, PREVIOUS, FOLLOWING = 13, 12, 10, 11   # button pictures
    NORMAL, PRESSED, DISABLED = 0, 1, 2
    # Frames per letter of a message by the text speed option, or letters per frame when negative
    SPEEDS = [3, 1, -2]

    class << self
      # The row and page each pocket was left at, and the item last used with its pocket: kept between battles
      def memory
        @memory ||= { rows: [0, 0, 0, 0], pages: [0, 0, 0, 0], item: nil, pocket: nil }
      end
    end

    def initialize(scene)
      @scene = scene
      @viewport = Viewport.new(0, Graphics.height, Graphics.width, Graphics.height)
      @viewport.z = 99999 + 50
      @font = B2W2.art("font.png", "BattleBag")
      @sprites = []
      sprite("background", 0)
      @panels = sprite(nil, 1)
      @text = sprite(nil, 20)
      @text.bitmap = Bitmap.new(512, 384)
      @cursor = Array.new(4) do |corner|
        bracket = sprite(nil, 40)
        bracket.bitmap = B2W2.art("cursor_#{corner}")
        bracket
      end
      @box = sprite(nil, 30)
      @box.bitmap = Bitmap.new(480, 64)
      @box.x = 16
      @box.y = 304
      @box.visible = false
      @black = sprite(nil, 90)
      @black.bitmap = Bitmap.new(512, 384)
      @black.bitmap.fill_rect(0, 0, 512, 384, Color.new(0, 0, 0))
      @buttons = []
      @icons = []
      @frames = 0
      @cursor_on = B2W2.lower.cursor_on
      memory = BattleBag.memory
      @rows = memory[:rows].clone
      @pages = memory[:pages].clone
      @last = memory[:item] if memory[:item] && $PokemonBag.pbHasItem?(memory[:item])
      @pocket = 0
      fill
      build(0)
      fade(false)
    end

    def sprite(name, z)
      sprite = Sprite.new(@viewport)
      sprite.bitmap = B2W2.art(name, "BattleBag") if name
      sprite.z = z
      @sprites.push(sprite)
      return sprite
    end

    def update; end

    def tick
      @frames += 1
      place_cursor
      @scene.updateWindow(self)
    end

    # To black or from it, an eighth a frame
    def fade(out)
      8.times do |step|
        @black.opacity = (out ? step + 1 : 7 - step) * 255 / 8
        tick
      end
    end

    def close
      B2W2.lower.cursor_on = @cursor_on
      fade(true)
      (@sprites + @buttons.compact + @icons).each(&:dispose)
      @text.bitmap.dispose
      @box.bitmap.dispose
      @viewport.dispose
    end

    #---------------------------------------------------------------------------
    # The pockets
    #---------------------------------------------------------------------------
    def pockets_of(data)
      return [2] if data.is_poke_ball?
      return [0, 1] if data.id == :FULLRESTORE
      return [1] if STATUS.include?(data.id)
      return [0] if [1, 2, 6, 7].include?(data.battle_use)
      return [3]
    end

    def fill
      @lists = Array.new(4) { [] }
      $PokemonBag.pockets.each do |pocket|
        next if !pocket
        pocket.each do |item, count|
          data = GameData::Item.try_get(item)
          next if !data || count == 0 || !data.battle_use || data.battle_use == 0
          pockets_of(data).each { |battle_pocket| @lists[battle_pocket].push(data.id) }
        end
      end
      4.times { |i| @pages[i] = [@pages[i], last_page(i)].min }
    end

    def last_page(pocket)
      return [(@lists[pocket].length - 1) / 6, 0].max
    end

    # The item in a slot of the pocket's page that shows
    def slot(index)
      return @lists[@pocket][@pages[@pocket] * 6 + index]
    end

    def item
      return slot(@rows[@pocket])
    end

    #---------------------------------------------------------------------------
    # Drawing
    #---------------------------------------------------------------------------
    def button(picture, x, y, state = NORMAL)
      button = Sprite.new(@viewport)
      button.z = 10
      button.x = x * 2
      button.y = y * 2
      @buttons.push(button)
      look(button, picture, state)
      return button
    end

    def look(button, picture, state)
      button.bitmap = B2W2.art("button_#{picture}_#{state}", "BattleBag")
    end

    def icon(item, x, y)
      icon = Sprite.new(@viewport)
      icon.bitmap = Bitmap.new(GameData::Item.icon_filename(item))
      icon.ox = icon.bitmap.width / 2
      icon.oy = icon.bitmap.height / 2
      icon.x = x * 2
      icon.y = y * 2
      icon.z = 15
      @icons.push(icon)
    end

    # Text in a window at (x, y): centred in the window's width if one is given
    def write(text, x, y, width = nil)
      x += (width - Font.width(text)) / 2 if width
      Font.draw(@text.bitmap, x, y, text, @font)
    end

    def count(item)
      return "x#{$PokemonBag.pbQuantity(item)}"
    end

    def build(page)
      @page = page
      (@buttons.compact + @icons).each(&:dispose)
      @buttons = []
      @icons = []
      @text.bitmap.clear
      @panels.bitmap = B2W2.art("panels_#{page}", "BattleBag")
      case page
      when 0
        [[5, 0, 8], [6, 0, 80], [7, 128, 8], [8, 128, 80]].each { |picture, x, y| button(picture, x, y) }
        button(BAR, 8, 152, @last ? NORMAL : DISABLED)
        button(BACK, 216, 152)
        [[0, 16, 32], [1, 16, 104], [2, 144, 40], [3, 144, 112]].each do |pocket, x, y|
          POCKET_NAMES[pocket].each_with_index { |line, i| write(line, x, y + 16 * i, 96) }
        end
        if @last
          write("LAST USED ITEM", 48, 168)
          icon(@last, 36, 180)
        end
        @stop = @cursor_on ? @pocket : 0
      when 1
        build_slots
        button(BACK, 216, 152)
        arrows = (last_page(@pocket) > 0) ? NORMAL : DISABLED
        button(PREVIOUS, 0, 152, arrows)
        button(FOLLOWING, 40, 152, arrows)
        lines = POCKET_NAMES[@pocket]
        lines.each_with_index { |line, i| write(line, 88, 152 + ((lines.length == 2) ? 4 + 16 * i : 12), 80) }
        @stop = @cursor_on ? @rows[@pocket] : 0
      when 2
        button(BAR, 8, 152)
        button(BACK, 216, 152)
        data = GameData::Item.get(item)
        write(data.name, 56, 32)
        write(count(data.id), 160, 32)
        wrap(data.description, 216).first(3).each_with_index { |line, i| write(line, 20, 72 + 16 * i) }
        write("USE", 64, 168, 88)
        icon(data.id, 40, 44)
        @stop = 0
      end
      @from = nil
    end

    # The six item panels of the pocket's page, their names, counts and icons, and the page number
    def build_slots
      @buttons.first(6).compact.each(&:dispose)
      @icons.each(&:dispose)
      @icons = []
      @text.bitmap.fill_rect(0, 0, 512, 304, Color.new(0, 0, 0, 0))
      @text.bitmap.fill_rect(336, 320, 80, 48, Color.new(0, 0, 0, 0))
      panels = Array.new(6) do |i|
        x = 128 * (i % 2)
        y = 48 * (i / 2)
        panel = Sprite.new(@viewport)
        panel.z = 10
        panel.x = x * 2
        panel.y = (8 + y) * 2
        look(panel, 9, slot(i) ? NORMAL : DISABLED)
        next panel if !slot(i)
        write(GameData::Item.get(slot(i)).name, 8 + x, 8 + y + 7, 112)
        write(count(slot(i)), 64 + x, 32 + y + 4)
        icon(slot(i), 36 + x, 45 + y)
        panel
      end
      @buttons[0, 6] = panels
      slash = 168 + (40 - Font.width("/")) / 2
      write("/", slash, 164)
      write((last_page(@pocket) + 1).to_s, slash + Font.width("/"), 164)
      now = (@pages[@pocket] + 1).to_s
      write(now, slash - Font.width(now), 164)
    end

    def wrap(text, width)
      lines = []
      text.split(" ").each do |word|
        if !lines.empty? && Font.width(lines.last + " " + word) <= width
          lines[-1] += " " + word
        else
          lines.push(word)
        end
      end
      return lines
    end

    # The cursor's four brackets at the corners of its button, stepping in and out
    def place_cursor
      stop = BUTTONS[@page][@stop]
      shown = @cursor_on && !@box.visible && stop && stop[1]
      inset = [-2, -1, 0][@frames / 12 % 3]
      @cursor.each_with_index do |bracket, corner|
        bracket.visible = shown
        next if !shown
        x, y, width, height = stop[1]
        bracket.x = ((corner < 2) ? x - width / 2 + inset + 1 : x + width / 2 - inset - 16) * 2
        bracket.y = (corner.even? ? y - height / 2 + inset : y + height / 2 - inset - 16) * 2
      end
    end

    # The pressed look for five frames, the normal one for three; then things go on
    def press(button, picture)
      look(button, picture, PRESSED)
      5.times { tick }
      look(button, picture, NORMAL)
      3.times { tick }
    end

    #---------------------------------------------------------------------------
    # Input
    #---------------------------------------------------------------------------
    # The button touched or chosen with Use this frame; Back chooses the last one that the keys reach. On the
    # item page, Left and Right where they lead nowhere answer :previous and :following.
    def choice
      tap = DualScreen.tap_in(@viewport)
      if tap
        @cursor_on = false
        return BUTTONS[@page].index do |(x, y, w, h), _|
          tap[0] >= x * 2 && tap[0] < (x + w) * 2 && tap[1] >= y * 2 && tap[1] < (y + h) * 2
        end
      end
      keys = [Input::UP, Input::DOWN, Input::LEFT, Input::RIGHT, Input::USE, Input::BACK]
      key = keys.index { |button| Input.trigger?(button) }
      return nil if !key
      if !@cursor_on
        # The first key only brings the cursor out
        @cursor_on = true
        @stop = 0 if !BUTTONS[@page][@stop][1]
        pbPlayCursorSE
        return nil
      end
      return @stop if key == 4
      return BUTTONS[@page].rindex { |button| button[1] } if key == 5
      target = BUTTONS[@page][@stop][2][key]
      target = (@from && @from != -target) ? @from : -target if target < 0
      if target == @stop
        return [:previous, :following][key - 2] if @page == 1 && key >= 2
        return nil
      end
      @from = @stop
      @stop = target
      pbPlayCursorSE
      return nil
    end

    # Goes through the pages until an item is to be used: the item, or nil when the bag is left
    def choose
      loop do
        tick
        chosen = choice
        next if !chosen
        case @page
        when 0
          if chosen.is_a?(Integer) && chosen < 4
            pbPlayDecisionSE
            @pocket = chosen
            press(@buttons[chosen], 5 + chosen)
            build(1)
          elsif chosen == 4
            next if !@last
            pbPlayDecisionSE
            press(@buttons[4], BAR)
            @pocket = BattleBag.memory[:pocket]
            place = @lists[@pocket].index(@last)
            @rows[@pocket] = place % 6
            @pages[@pocket] = place / 6
            build(2)
          elsif chosen == 5
            pbPlayCancelSE
            press(@buttons[5], BACK)
            return nil
          end
        when 1
          if chosen == 6
            pbPlayCancelSE
            press(@buttons[6], BACK)
            build(0)
          elsif chosen.is_a?(Integer) && chosen < 6
            next if !slot(chosen)
            pbPlayDecisionSE
            @rows[@pocket] = chosen
            press(@buttons[chosen], 9)
            build(2)
          else
            next if last_page(@pocket) == 0
            back = [7, :previous].include?(chosen)
            pbPlayDecisionSE
            @rows[@pocket] = 0 if chosen.is_a?(Integer)
            press(@buttons[back ? 7 : 8], back ? PREVIOUS : FOLLOWING)
            @pages[@pocket] = (@pages[@pocket] + (back ? -1 : 1)) % (last_page(@pocket) + 1)
            build_slots
          end
        when 2
          if chosen == 0
            pbPlayDecisionSE
            press(@buttons[0], BAR)
            return item
          elsif chosen == 1
            pbPlayCancelSE
            press(@buttons[1], BACK)
            build(1)
          end
        end
      end
    end

    # The item was used: this is where the bag opens next time
    def remember
      BattleBag.memory.update(rows: @rows, pages: @pages, item: item, pocket: @pocket)
    end

    #---------------------------------------------------------------------------
    # Messages, which the battle shows through this screen when an item cannot be used
    #---------------------------------------------------------------------------
    def pbDisplay(text)
      lines = wrap(text, 224)
      speed = SPEEDS[$PokemonSystem.textspeed] || -4
      @box.visible = true
      lines.each_slice(2) do |pair|
        letters = 0
        total = pair.sum(&:length)
        wait = 0
        loop do
          hurry = DualScreen.tap || Input.press?(Input::USE) || Input.press?(Input::BACK)
          if wait <= 0
            letters = hurry ? total : [letters + ((speed < 0) ? -speed : 1), total].min
            wait = [speed, 0].max
            @box.bitmap.fill_rect(0, 0, 480, 64, Color.new(40, 40, 48))
            @box.bitmap.fill_rect(0, 0, 480, 2, Color.new(200, 200, 208))
            @box.bitmap.fill_rect(0, 62, 480, 2, Color.new(200, 200, 208))
            first = pair[0][0, letters]
            second = (pair[1] || "")[0, [letters - pair[0].length, 0].max]
            Font.draw(@box.bitmap, 8, 1, first)
            Font.draw(@box.bitmap, 8, 17, second)
          end
          wait -= 1
          tick
          break if letters == total
        end
        loop do
          tick
          break if DualScreen.tap || Input.trigger?(Input::USE) || Input.trigger?(Input::BACK)
        end
        pbPlayDecisionSE
      end
      @box.visible = false
    end
    alias pbDisplayPaused pbDisplay
  end
end
