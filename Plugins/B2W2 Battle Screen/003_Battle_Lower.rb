#===============================================================================
# The battle's lower screen as it is in Black 2 and White 2: standby, the
# command screen, the move screen and the target screen, with their
# transitions, press flash, key cursor and touch areas. Layout, tables and
# frame counts are White 2's. Positions are in DS pixels and drawn at twice the
# size; a frame is 1/60 s, which is the game's own frame here.
#===============================================================================
module B2W2
  class BattleLower
    # Touch areas (x, y, width, height). Command: FIGHT, BAG, POKéMON, RUN or back. Moves: the four tiles, cancel.
    COMMAND_AREAS = [[0, 24, 256, 120], [0, 144, 80, 48], [176, 144, 80, 48], [88, 152, 80, 40]]
    MOVE_AREAS    = [[0, 32, 128, 48], [128, 32, 128, 48], [0, 80, 128, 48], [128, 80, 128, 48], [176, 144, 80, 48]]
    # Target: a panel per position, numbered as the battlers are, then cancel
    TARGET_AREAS  = { 2 => [[0, 88, 128, 40], [128, 32, 128, 56], [128, 88, 128, 40], [0, 32, 128, 56],
                            [176, 144, 80, 48]],
                      3 => [[8, 88, 80, 40], [168, 32, 80, 56], [88, 88, 80, 40], [88, 32, 80, 56],
                            [168, 88, 80, 40], [8, 32, 80, 56], [176, 144, 80, 48]] }
    # Where the key cursor goes from each stop on Up, Down, Left, Right. A negative entry is the stop it last
    # came from, or that stop if there is none.
    COMMAND_MOVES = [[nil, -1, 1, 2], [0, nil, nil, 3], [0, nil, 3, nil], [0, nil, 1, 2]]
    MOVE_MOVES    = [[nil, 2, nil, 1], [nil, 3, 0, nil], [0, 4, nil, 3], [1, 4, 2, nil], [-2, nil, nil, nil]]
    CANCEL        = 4
    # The palette row of each target panel, which is what a press flashes
    PANEL_ROWS    = { 2 => [9, 8, 10, 7], 3 => [10, 9, 11, 8, 12, 7] }
    # In the text window: where each panel's name is centred
    NAMES_AT      = { 2 => [[64, 68], [192, 20], [192, 68], [64, 20]],
                      3 => [[48, 68], [208, 20], [128, 68], [128, 20], [208, 68], [48, 20]] }
    # White 2's number for what a move can be aimed at, which with the user's place picks the outlines and the
    # cursor's stops. 14 is its "any other Pokémon" of triple battles.
    RANGES = { NearOther: 0, UserOrNearAlly: 1, NearAlly: 2, NearFoe: 3, AllNearOthers: 4, AllNearFoes: 5,
               UserAndAllies: 6, User: 7, AllBattlers: 8, RandomNearFoe: 9, BothSides: 10, FoeSide: 11,
               UserSide: 12, None: 13, Other: 14, Foe: 3, AllFoes: 11, AllAllies: 6 }
    # Each of the cursor's six brackets: its picture, and which corner of its rectangle it sits on
    BRACKETS = [[0, :left, :top], [2, :right, :top], [1, :left, :bottom], [3, :right, :bottom],
                [1, :left, :bottom], [3, :right, :bottom]]
    TILE_CENTRES  = [[64, 56], [192, 56], [64, 104], [192, 104]]
    ICON_CENTRES  = [[34, 65], [162, 65], [34, 113], [162, 113]]
    # In the text window, whose corner is at (0, 32): a move's name is centred on the first, "PP" starts at the
    # second, the PP numbers are centred on the third
    # The player's Pokémon on the command screen of a double or triple battle, by how many there are
    MONS_AT       = { 2 => [[104, 112], [152, 112]], 3 => [[88, 112], [128, 112], [168, 112]] }
    TEXT_AT       = [[[64, 10], [53, 26], [90, 26]], [[192, 10], [181, 26], [218, 26]],
                     [[64, 58], [53, 74], [90, 74]], [[192, 58], [181, 74], [218, 74]]]
    # White 2's type numbers, which pick a tile's colours and its type icon
    TYPES = [:NORMAL, :FIGHTING, :FLYING, :POISON, :GROUND, :ROCK, :BUG, :GHOST, :STEEL, :FIRE, :WATER, :GRASS,
             :ELECTRIC, :PSYCHIC, :ICE, :DRAGON, :DARK]
    EMPTY_TILE  = 17
    FLASH       = [2, 4, 6, 8, 6, 4, 2, 0]   # sixteenths toward white, one frame each
    GROW        = [1.0, 1.2, 1.4, 1.6, 1.8]
    CLOSE_AFTER = 12   # frames without a menu before the screen goes back to standby

    attr_reader :screen
    # Whether the key cursor is out, which the battle's other screens take over and hand back
    attr_accessor :cursor_on

    def initialize(viewport, scene, battle)
      @viewport = viewport
      @scene = scene
      @battle = battle
      @sprites = []
      @tasks = []
      @memory = {}
      @frames = 0
      @screen = :standby
      @ball = sprite("ball", 0)
      @ball_dim = sprite("ball_dim", 1)
      [@ball, @ball_dim].each do |ball|
        ball.ox = ball.oy = 256
        ball.x = 256
      end
      @field = sprite(nil, 10)
      @field_dim = sprite(nil, 11)
      @field_dim.color = Color.new(16, 16, 16)
      @field_flash = sprite(nil, 12)
      @tiles = sprite(nil, 13)
      @tiles.bitmap = Bitmap.new(512, 192)
      @tiles.y = 64
      @tile_flash = sprite(nil, 14)
      @tile_flash.bitmap = @tiles.bitmap
      @buttons = sprite(nil, 20)
      @button_flash = sprite(nil, 21)
      @outlines = sprite(nil, 22)
      @panel_flash = Array.new(6) { sprite(nil, 12) }
      @text = sprite(nil, 30)
      @text.bitmap = Bitmap.new(512, 384)
      ([@field_flash, @tile_flash, @button_flash] + @panel_flash).each do |flash|
        flash.color = Color.new(255, 255, 255)
        flash.opacity = 0
      end
      @balls = Array.new(6) { |i| ball_sprite(88 + 16 * i, 136, 0) }
      @foe_balls = Array.new(6) { |i| ball_sprite(148 - 8 * i, 48, 1) }
      @grow = TILE_CENTRES.map do |x, y|
        tile = sprite("tile_grow", 40)
        tile.ox = tile.bitmap.width / 2
        tile.oy = tile.bitmap.height / 2
        tile.x = x * 2
        tile.y = y * 2
        tile
      end
      @icons = ICON_CENTRES.map do |x, y|
        icon = sprite("types", 41)
        icon.ox = 32
        icon.oy = 16
        icon.x = x * 2
        icon.y = y * 2
        icon
      end
      @mons = Array.new(3) { sprite(nil, 40) }
      @cursor = BRACKETS.map { |picture, _, _| sprite("cursor_#{picture}", 50) }
      (@grow + @icons + @cursor + @mons + @balls + @foe_balls + [@tiles, @field, @field_dim, @buttons, @outlines]).each do |sprite|
        sprite.visible = false
      end
      self.field = 372
      self.buttons = 361
      ball_at(3.0, 152)
      self.dim = 12
    end

    def sprite(name, z)
      sprite = Sprite.new(@viewport)
      sprite.bitmap = B2W2.art(name) if name
      sprite.z = z
      @sprites.push(sprite)
      return sprite
    end

    # A party ball: the large ones are the player's, the small ones the foe's
    def ball_sprite(x, y, row)
      ball = sprite("balls", 40)
      size = (row == 0) ? 32 : 16
      ball.src_rect.set(0, row * 32, size, size)
      ball.ox = ball.oy = size / 2
      ball.x = x * 2
      ball.y = y * 2
      return ball
    end

    def dispose
      @sprites.each(&:dispose)
      @tiles.bitmap.dispose
      @text.bitmap.dispose
    end

    # The scene's frame update calls this for whatever menu is open; the screen moves in frame instead
    def update; end

    #---------------------------------------------------------------------------
    # Layers
    #---------------------------------------------------------------------------
    # The Poké Ball picture. The scale is the game's: 3.0 shows it at a third of its size. y is its scroll.
    def ball_at(scale, y)
      [@ball, @ball_dim].each do |ball|
        ball.zoom_x = ball.zoom_y = 2.0 / scale
        ball.y = (256 - y) * 2
      end
    end

    def ball=(shown)
      @ball.visible = @ball_dim.visible = shown
    end

    def field=(map)
      @field.bitmap = B2W2.art("field_#{map}")
      @field_dim.bitmap = @field_flash.bitmap = B2W2.art("field_#{map}_rows01") if map != @rule_field
    end

    # Which 256x192 part of the field map shows
    def field_at(x, y)
      [@field, @field_dim, @field_flash].each { |layer| layer.src_rect.set(x * 2, y * 2, 512, 384) }
    end

    def field_shown=(shown)
      @field.visible = @field_dim.visible = shown
    end

    def buttons=(map)
      @map = map
      @buttons.bitmap = @button_flash.bitmap = B2W2.art("buttons_#{map}")
    end

    # Which part of the button map shows. The map wraps round: from 448 up its top edge is still below the top
    # of the screen, which is how the buttons rise into view.
    def buttons_at(x, y)
      @buttons_x = x
      @buttons.src_rect.set(x * 2, 0, 512, 384)
      @buttons.y = (y >= 320 ? 512 - y : -y) * 2
    end

    # Palette rows 0 and 1, the ball's and FIGHT's colours, blended toward dark grey: 12 in standby, 0 in a menu
    def dim=(sixteenths)
      @dim = sixteenths
      @ball_dim.opacity = sixteenths * 255 / 12
      @field_dim.opacity = sixteenths * 255 / 16
    end

    #---------------------------------------------------------------------------
    # Tasks: everything that moves runs one step per frame
    #---------------------------------------------------------------------------
    # Starts a task; what it does before its first wait happens at once
    def start(&block)
      task = Fiber.new(&block)
      task.resume
      @tasks.push(task) if task.alive?
      return task
    end

    def wait(frames = 1)
      frames.times { Fiber.yield }
    end

    def join(*tasks)
      Fiber.yield while tasks.any?(&:alive?)
    end

    def busy?
      return !@tasks.empty?
    end

    # Called once per frame
    def frame
      @frames += 1
      @tasks.dup.each { |task| task.resume if task.alive? }
      @tasks.reject! { |task| !task.alive? }
      place_cursor
      # The icon of the Pokémon whose turn it is to choose hops
      @mons.each { |mon| mon.src_rect.x = (mon.color.alpha == 0 && @frames / 8 % 2 == 1) ? 64 : 0 if mon.visible }
      return if !@close_in || busy?
      @close_in -= 1
      return if @close_in > 0
      @close_in = nil
      start { to_standby }
    end

    # One frame of the battle with this screen in it
    def tick
      @scene.updateWindow(self)
    end

    # Runs a transition to its end
    def play(&block)
      tick while busy?
      start(&block)
      tick while busy?
    end

    #---------------------------------------------------------------------------
    # The animations the transitions are made of
    #---------------------------------------------------------------------------
    def ball_scale(from, to, step, y)
      start do
        scale = from
        ball_at(scale, y)
        while scale != to
          wait
          scale += step
          y += (step < 0) ? 2 : -2
          ball_at(scale, y)
        end
      end
    end

    def button_rise(x, y, step, count)
      start do
        buttons_at(x, y)
        count.times do
          wait
          y += step
          buttons_at(x, y)
        end
      end
    end

    # The field opening for the move screen (way 0) or closing again (way 1), a picture every two frames
    def field_frames(way)
      start do
        wait(2)
        field_at(256, 0)
        wait(2)
        field_at(0, (way == 0) ? 192 : 0)
      end
    end

    def tile_grow(shrink)
      start do
        (shrink ? GROW.reverse : GROW).each do |scale|
          @grow.each_with_index do |tile, i|
            tile.visible = !@moves[i].nil?
            tile.zoom_x = tile.zoom_y = scale
          end
          wait
        end
        # Grown tiles stay until the move screen's own tiles take their place
        @grow.each { |tile| tile.visible = false } if shrink
      end
    end

    # The foe's party balls make room for the move tiles (way 0) and come back (way 1)
    def slide(way)
      start do
        target = (way == 0) ? 24 : 48
        while @foe_balls[0].y != target * 2
          @foe_balls.each { |ball| ball.y += (ball.y < target * 2) ? 8 : -8 }
          wait
        end
      end
    end

    # One step every second frame
    def fade(to)
      @fade = start do
        while @dim != to
          wait(2)
          self.dim = @dim + ((to > @dim) ? 2 : -2)
        end
      end
    end

    def flash(layer)
      start do
        FLASH.each do |sixteenths|
          layer.opacity = sixteenths * 255 / 16
          wait
        end
      end
    end

    #---------------------------------------------------------------------------
    # Transitions
    #---------------------------------------------------------------------------
    def to_command(map)
      leave_target if @screen == :target
      if @screen == :standby || @screen == :target
        self.buttons = map
        self.field = 372
        field_at(0, 0)
        pbSEPlay("EBDX/SE_Zoom4", 50)
        self.field_shown = false
        @buttons.visible = true
        self.ball = true
        show_balls
        show_mons
        fade(0)
        join(ball_scale(3.0, 1.0, -0.25, 152), button_rise(0, 448, 8, 8))
        self.field_shown = true
        self.ball = false
      elsif @screen == :moves
        self.buttons = map
        self.field = 372
        field_at(0, 192)
        hide_moves
        show_mons
        wait
        shrink = tile_grow(true)
        wait(4)
        join(shrink, button_rise(0, 448, 8, 8), field_frames(1), slide(1))
      end
      @screen = :command
    end

    def to_moves
      if @screen == :standby
        self.buttons = 361
        self.field = 379
        field_at(0, 0)
        pbSEPlay("EBDX/SE_Zoom4", 50)
        self.field_shown = false
        @buttons.visible = false
        self.ball = true
        show_balls
        fade(0)
        join(ball_scale(3.0, 1.0, -0.25, 152))
        self.field_shown = true
        @buttons.visible = true
        self.ball = false
      end
      @mons.each { |mon| mon.visible = false }
      moving = [button_rise(256, 448, 8, 8), field_frames(0), slide(0)]
      wait(4)
      join(tile_grow(false), *moving)
      show_moves
      field_at(256, 192)
      @screen = :moves
    end

    def to_standby
      return if @screen == :standby
      (@balls + @foe_balls + @mons).each { |ball| ball.visible = false }
      @cursor_on = false
      fade(12)
      if @screen == :moves || @screen == :target
        shrink = (@screen == :moves)
        leave_target if @screen == :target
        self.buttons = 361
        self.field = 378
        field_at(0, 192)
        hide_moves
        wait
        tiles = shrink ? tile_grow(true) : nil
        wait(4)
        join(*[tiles, field_frames(1)].compact)
      end
      closing = ball_scale(1.0, 3.0, 0.25, 168)
      wait
      self.field_shown = false
      @buttons.visible = false
      self.ball = true
      join(closing)
      @screen = :standby
    end

    # The target screen takes the move screen's place at once
    def to_target(layout)
      hide_moves
      self.field = @rule_field
      field_at(0, 0)
      @outlines.bitmap = B2W2.art("target_#{layout}")
      @outlines.visible = true
      show_names
      @screen = :target
    end

    def leave_target
      @outlines.visible = false
      @text.bitmap.clear
      @rule_field = nil
    end

    def target_to_moves
      leave_target
      self.field = 372
      field_at(0, 192)
      wait
      show_moves
      field_at(256, 192)
      @screen = :moves
    end

    #---------------------------------------------------------------------------
    # What is on the screens
    #---------------------------------------------------------------------------
    # 0 no Pokémon, 1 fine, 2 fainted, 3 with a status problem
    def ball_state(pokemon)
      return 0 if !pokemon
      return 2 if pokemon.fainted?
      return (pokemon.status == :NONE) ? 1 : 3
    end

    def show_balls
      party = @battle.pbParty(@battler.index)
      @balls.each_with_index do |ball, i|
        ball.src_rect.x = ball_state(party[i]) * 32
        ball.visible = true
      end
      return if !@battle.trainerBattle?
      party = @battle.pbParty(@battler.index ^ 1)
      @foe_balls.each_with_index do |ball, i|
        ball.src_rect.x = ball_state(party[i]) * 32
        ball.y = 96
        ball.visible = true
      end
    end

    # In a double or triple battle, the player's Pokémon: the one choosing now as it is, the others darkened
    def show_mons
      places = MONS_AT[@battle.pbSideSize(@battler.index)]
      @mons.each { |mon| mon.visible = false }
      return if !places
      @battle.eachSameSideBattler(@battler.index) do |battler|
        mon = @mons[battler.index / 2]
        mon.bitmap = Bitmap.new(GameData::Species.icon_filename_from_pokemon(battler.displayPokemon))
        mon.src_rect.set(0, 0, 64, 64)
        mon.ox = mon.oy = 32
        mon.x, mon.y = places[battler.index / 2].map { |place| place * 2 }
        mon.color = Color.new(0, 0, 0, (battler.index == @battler.index) ? 0 : 128)
        mon.visible = true
      end
    end

    # The colour pair of a move's PP: white, then yellow, orange and red as it runs out
    def pp_colour(now, most)
      return 3 if now == 0
      return 0 if now == most
      return (now == 1) ? 2 : 0 if most < 3
      return (now == 1) ? 2 : (now == 2) ? 1 : 0 if most < 8
      return 2 if now <= most / 4
      return 1 if now <= most / 2
      return 0
    end

    def move_type(move)
      type = @scene.b2w2_move_type(@battler, GameData::Move.get(move.id))
      return TYPES.index(type) || 0
    end

    def show_moves
      @tiles.bitmap.clear
      @text.bitmap.clear
      4.times do |i|
        move = @moves[i]
        type = move ? move_type(move) : EMPTY_TILE
        part = Rect.new(i % 2 * 256, i / 2 * 96, 256, 96)
        @tiles.bitmap.blt(part.x, part.y, B2W2.art(format("tiles_%02d", type)), part)
        @icons[i].visible = !move.nil?
        next if !move
        @icons[i].src_rect.set(0, type * 32, 64, 32)
        name, label, count = TEXT_AT[i]
        colour = pp_colour(move.pp, move.total_pp)
        Font.draw(@text.bitmap, name[0], name[1] + 32, move.name, 0, true)
        Font.draw(@text.bitmap, label[0], label[1] + 32, "PP", colour)
        Font.draw(@text.bitmap, count[0], count[1] + 32, format("%2d/%2d", move.pp, move.total_pp), colour, true)
      end
      @tiles.visible = true
      @grow.each { |tile| tile.visible = false }
    end

    # Every Pokémon in the battle on its panel, with the mark of its sex
    def show_names
      @text.bitmap.clear
      NAMES_AT[@rule].each_with_index do |(x, y), i|
        battler = @battle.battlers[i]
        next if !battler || battler.fainted?
        mark = ["♂", "♀"][battler.displayGender] || ""
        Font.draw(@text.bitmap, x, y + 32, battler.name + mark, 0, true)
      end
    end

    def hide_moves
      @text.bitmap.clear
      @tiles.visible = false
      @icons.each { |icon| icon.visible = false }
    end

    #---------------------------------------------------------------------------
    # Input
    #---------------------------------------------------------------------------
    # A screen's touch areas, which of them answer, and the cursor's stops: for each the rectangles its brackets
    # sit on, where the arrow keys lead, and the area Use chooses
    def input(areas, stops, enabled = nil)
      @areas = areas
      @stops = stops
      @enabled = enabled || Array.new(areas.length, true)
    end

    # Stops of a screen where every area is one stop
    def plain_stops(moves)
      return moves.each_with_index.map { |links, i| [[i, i, i, i, -1, -1], links, i] }
    end

    # White 2's stops for a target screen: the outlines' picture, then the stops
    def self.targets
      if !@targets
        @targets = {}
        File.readlines(ART + "Battle/targets.txt").each do |line|
          rule, user, range, layout, *stops = line.split
          stops = stops.map do |stop|
            values = stop.split(",").map(&:to_i)
            [values[0, 6], values[6, 4].map { |link| (link == -128) ? nil : link }, values[10]]
          end
          @targets[[rule.to_i, user.to_i, range.to_i]] = [layout.to_i, stops]
        end
      end
      return @targets
    end

    # The cursor's brackets at the corners of its stop, stepping in and out
    def place_cursor
      shown = @cursor_on && @stop && !busy? && @screen != :standby
      inset = [-2, -1, 0][@frames / 12 % 3]
      @cursor.each_with_index do |bracket, i|
        area = shown ? @stops[@stop][0][i] : -1
        bracket.visible = area >= 0
        next if area < 0
        x, y, width, height = @areas[area]
        _, side, edge = BRACKETS[i]
        bracket.x = ((side == :left) ? x + inset + 1 : x + width - inset - 16) * 2
        bracket.y = ((edge == :top) ? y + inset : y + height - inset - 16) * 2
      end
    end

    # The area touched this frame, or the one the keys chose: Use chooses the cursor's stop, Back the given area
    def choice(back)
      tap = DualScreen.tap_in(@viewport)
      if tap
        @cursor_on = false
        return @areas.index { |x, y, w, h| tap[0] >= x * 2 && tap[0] < (x + w) * 2 && tap[1] >= y * 2 && tap[1] < (y + h) * 2 }
      end
      return back if back && Input.trigger?(Input::BACK)
      way = [Input::UP, Input::DOWN, Input::LEFT, Input::RIGHT].index { |key| Input.trigger?(key) }
      use = Input.trigger?(Input::USE)
      return nil if !way && !use
      if !@cursor_on
        # The first key only brings the cursor out
        @cursor_on = true
        pbPlayCursorSE
        return nil
      end
      return @stops[@stop][2] if use
      target = @stops[@stop][1][way]
      return nil if !target
      target = (@from && @from != -target) ? @from : -target if target < 0
      @from = @stop
      @stop = target
      pbPlayCursorSE
      yield @stops[@stop][2] if block_given?
      return nil
    end

    # Flashes the layers given, or the button of an area; input stays shut until it is over
    def press(area, layers = nil)
      x, y, width, height = @areas[area]
      if !layers
        layers = [@button_flash]
        @button_flash.src_rect.set((@buttons_x + x) * 2, y * 2, width * 2, height * 2)
        @button_flash.x = x * 2
        @button_flash.y = y * 2
      end
      play { join(*layers.map { |layer| flash(layer) }) }
    end

    def press_tile(area)
      x, y, width, height = @areas[area]
      @tile_flash.src_rect.set(x * 2, (y - 32) * 2, width * 2, height * 2)
      @tile_flash.x = x * 2
      @tile_flash.y = y * 2
      press(area, [@tile_flash])
    end

    # The command screen, until a command is chosen: 0 FIGHT, 1 BAG, 2 POKéMON, 3 RUN, or back when there is a
    # Pokémon to go back to
    def command(battler, back)
      @close_in = nil
      @battler = battler
      play { to_command(back ? 364 : 361) }
      input(COMMAND_AREAS, plain_stops(COMMAND_MOVES))
      @stop = @memory[[battler.index, :command]] || 0
      @from = nil
      chosen = nil
      loop do
        tick
        chosen = choice(back ? 3 : nil)
        break if chosen
      end
      @memory[[battler.index, :command]] = chosen
      (chosen == 3 && back) ? pbPlayCancelSE : pbPlayDecisionSE
      press(chosen, (chosen == 0) ? [@field_flash] : nil)
      if chosen == 0
        @close_in = CLOSE_AFTER   # unless the move screen follows
      else
        play { to_standby }
      end
      return chosen
    end

    # Brings up the move screen for a Pokémon
    def open_moves(battler, index)
      @close_in = nil
      @battler = battler
      @moves = battler.moves
      if @screen == :moves
        tick while busy?
        show_moves
      else
        play { to_moves }
      end
      @stop = index
      @from = nil
    end

    # The move screen, until something is chosen: a move's number, -1 for cancel, -2 for the Action button
    def move
      play { target_to_moves } if @screen == :target
      input(MOVE_AREAS, plain_stops(MOVE_MOVES))
      loop do
        tick
        return -2 if Input.trigger?(Input::ACTION)
        chosen = choice(CANCEL)
        next if !chosen
        if chosen == CANCEL
          pbPlayCancelSE
          press(chosen)
          return -1
        end
        next if !@moves[chosen]
        if @moves[chosen].pp == 0 && @moves[chosen].total_pp > 0
          pbPlayBuzzerSE
          next
        end
        pbPlayDecisionSE
        press_tile(chosen)
        return chosen
      end
    end

    # The target screen for the move just chosen, until a target is: a battler's number, or -1 for cancel.
    # names holds a name for every battler that can be aimed at; grouped, they are all hit and chosen as one.
    # The block is told the battler the cursor moves to.
    def target(battler, range, names, grouped, first)
      @rule = [@battle.pbSideSize(0), @battle.pbSideSize(1)].max
      @rule_field = (@rule == 3) ? 374 : 373
      range = 0 if range == 14 && @rule == 2
      layout, stops = BattleLower.targets[[@rule, battler.index / 2, range]]
      cancel = TARGET_AREAS[@rule].length - 1
      play { to_target(layout) }
      input(TARGET_AREAS[@rule], stops, Array.new(cancel) { |i| !names[i].nil? } + [true])
      @stop = stops.index { |stop| stop[2] == first } || 0
      @from = nil
      rows = PANEL_ROWS[@rule]
      @panel_flash.each_with_index do |flash, i|
        flash.bitmap = rows[i] ? B2W2.art("field_#{@rule_field}_row#{rows[i]}") : nil
      end
      loop do
        tick
        chosen = choice(cancel) { |aimed| yield aimed if !grouped && aimed != cancel && names[aimed] }
        next if !chosen || !@enabled[chosen]
        if chosen == cancel
          pbPlayCancelSE
          press(chosen)
          play { target_to_moves }
          return -1
        end
        pbPlayDecisionSE
        press(chosen, grouped ? @panel_flash.select.with_index { |_, i| names[i] } : [@panel_flash[chosen]])
        return chosen
      end
    end

    # The whole screen fades to black before another program takes it over, and back afterwards
    def blackout(out)
      @black ||= sprite(nil, 90)
      @black.bitmap ||= Bitmap.new(512, 384).tap { |bitmap| bitmap.fill_rect(0, 0, 512, 384, Color.new(0, 0, 0)) }
      play do
        8.times do |step|
          @black.opacity = (out ? step + 1 : 7 - step) * 255 / 8
          wait(2)
        end
      end
    end

    # The menus are done for now: standby, unless another menu comes first
    def close_later
      @close_in = CLOSE_AFTER
    end
  end
end
