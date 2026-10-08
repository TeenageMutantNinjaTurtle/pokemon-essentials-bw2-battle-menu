#===============================================================================
# Second screen: a touch screen below the game's own picture, which holds the
# battle menus. With one screen, nothing here does anything.
#===============================================================================
module DualScreen
  @frame = 0
  @lower = 0

  class << self
    # Frames drawn so far
    attr_accessor :frame
  end

  # Whether the engine has a second screen of its own to ask about
  ENGINE_SCREENS = Graphics.respond_to?(:screen_mode)

  # :single for one screen, :stacked for the lower screen under the upper one in one window, :split for the two
  # apart. An engine without a second screen gets one from DUAL_SCREEN=stacked: the window is made twice as tall.
  def self.mode
    return Graphics.screen_mode if ENGINE_SCREENS
    return (ENV["DUAL_SCREEN"] == "stacked") ? :stacked : :single
  end

  def self.on?
    return mode != :single
  end

  # Whether the second screen is the lower half of a window this plugin doubled
  def self.own_window?
    return !ENGINE_SCREENS && on?
  end

  # The lower screen. Positions inside it start at its top left corner.
  def self.viewport
    if !@viewport || @viewport.disposed?
      @viewport = Viewport.new(0, Graphics.height, Graphics.width, Graphics.height)
      @viewport.z = 99999
    end
    return @viewport
  end

  # Viewports made inside the block are put on the lower screen
  def self.lower
    @lower += 1
    yield
  ensure
    @lower -= 1
  end

  def self.lower?
    return @lower > 0
  end

  def self.update
    @press = nil
    @tap = nil
    @list_open = false
    return if !on? || !Input.dual_trigger?(Input::MOUSELEFT)
    y = Input.mouse_y - Graphics.height
    @tap = [Input.mouse_x, y] if y >= 0
  end

  # Where the lower screen was touched this frame, or nil
  def self.tap
    return @tap
  end

  # Where this frame's touch is inside a viewport on the lower screen, or nil
  def self.tap_in(viewport)
    return nil if !@tap || !viewport || viewport.disposed? || viewport.rect.y < Graphics.height
    return [@tap[0] - viewport.rect.x + viewport.ox, @tap[1] - viewport.rect.y + Graphics.height + viewport.oy]
  end

  # Whether the touch is inside this rectangle of a viewport
  def self.touched_at?(viewport, x, y, width, height)
    tap = tap_in(viewport)
    return tap && tap[0] >= x && tap[0] < x + width && tap[1] >= y && tap[1] < y + height
  end

  # A list of choices is taking input this frame, so what lies under it is not to be touched
  def self.list_open
    @list_open = true
  end

  def self.list_open?
    return @list_open
  end

  # Makes the game see one press of a button, as if it came from the keyboard
  def self.press(button)
    @press = button
  end

  def self.pressed?(button)
    return false if @press != button
    @press = nil
    return true
  end

  # A menu of this battle is open on the lower screen while the block runs
  def self.battle_menu(scene)
    @battle_scene = scene
    yield
  ensure
    @battle_scene = nil
  end

  def self.battle_menu?
    return !@battle_scene.nil?
  end

  def self.animate_battle
    return if !@battle_scene || @animating
    @animating = true
    @battle_scene.dual_animate
  ensure
    @animating = false
  end
end

class << Graphics
  alias dual_resize_screen resize_screen
  def resize_screen(width, height)
    dual_resize_screen(width, DualScreen.own_window? ? height * 2 : height)
  end

  alias dual_height height
  def height
    return DualScreen.own_window? ? dual_height / 2 : dual_height
  end

  alias dual_update update
  def update
    DualScreen.animate_battle
    dual_update
    DualScreen.frame += 1
  end
end

class << Input
  alias dual_update update
  def update
    dual_update
    DualScreen.update
  end

  alias dual_trigger? trigger?
  def trigger?(button)
    return DualScreen.pressed?(button) || dual_trigger?(button)
  end

  alias dual_press? press?
  def press?(button)
    return DualScreen.pressed?(button) || dual_press?(button)
  end
end

class Viewport
  alias dual_initialize initialize
  def initialize(*args)
    dual_initialize(*args)
    self.rect = Rect.new(rect.x, rect.y + Graphics.height, rect.width, rect.height) if DualScreen.lower?
  end
end

Graphics.resize_screen(Settings::SCREEN_WIDTH, Settings::SCREEN_HEIGHT) if DualScreen.own_window?
