#===============================================================================
# Where the lower screen meets the game: the battle scene of Elite Battle DX
# opens the screens above instead of its own menus, and the game's party screen
# opens below when a battle calls for it. The methods replaced here follow the
# ones of Pokémon Essentials (CC BY-NC-SA 4.0) and Elite Battle DX they stand
# in for.
#===============================================================================
class << Graphics
  alias b2w2_update update
  def update
    B2W2.lower.frame if B2W2.lower
    b2w2_update
  end
end

class PokeBattle_Scene
  alias b2w2_loadUIElements loadUIElements
  def loadUIElements
    b2w2_loadUIElements
    B2W2.lower = B2W2::BattleLower.new(DualScreen.viewport, self, @battle) if DualScreen.on?
  end

  alias b2w2_pbDisposeSprites pbDisposeSprites
  def pbDisposeSprites
    b2w2_pbDisposeSprites
    return if !B2W2.lower
    B2W2.lower.dispose
    B2W2.lower = nil
  end

  # A move's type as the battle shows it (the move menu works it out)
  def b2w2_move_type(battler, data)
    return @fightWindow.GetProperType(battler, data).id
  end

  # Safari and other battles with their own commands keep the game's menu
  alias b2w2_pbCommandMenuEx pbCommandMenuEx
  def pbCommandMenuEx(idxBattler, texts, mode = 0)
    return b2w2_pbCommandMenuEx(idxBattler, texts, mode) if mode > 1 || !B2W2.lower
    self.clearMessageWindow
    @ret = 0
    @vector.reset
    @inCMx = true
    @sprites["dataBox_#{idxBattler}"].selected = true
    @ret = B2W2.lower.command(@battle.battlers[idxBattler], mode == 1)
    @inCMx = false if @battle.doublebattle? && @ret > 0
    @lastcmd[idxBattler] = @ret
    if @ret > 0
      @vector.set(EliteBattle.get_vector(:MAIN, @battle))
      @vector.inc = 0.2
    end
    self.pbDeselectAll
    return @ret
  end

  # What a move is aimed at, when the battle asks in the middle of the move screen
  alias b2w2_pbChooseTarget pbChooseTarget
  def pbChooseTarget(idxBattler, target_data, visibleSprites = nil)
    range = B2W2::BattleLower::RANGES[target_data.id]
    if !B2W2.lower || B2W2.lower.screen != :moves || !range || @battle.pbSideSize(0) + @battle.pbSideSize(1) < 3
      return b2w2_pbChooseTarget(idxBattler, target_data, visibleSprites)
    end
    texts = pbCreateTargetTexts(idxBattler, target_data)
    grouped = target_data.num_targets != 1
    first = pbFirstTarget(idxBattler, target_data)
    pbSelectBattler(grouped ? texts : first, 2)
    ret = B2W2.lower.target(@battle.battlers[idxBattler], range, texts, grouped, first) do |index|
      pbSelectBattler(index)
    end
    self.pbDeselectAll((ret < 0) ? idxBattler : nil)
    return ret
  end

  alias b2w2_pbFightMenu pbFightMenu
  def pbFightMenu(idxBattler, megaEvoPossible = false, &block)
    return b2w2_pbFightMenu(idxBattler, megaEvoPossible, &block) if !B2W2.lower
    battler = @battle.battlers[idxBattler]
    self.clearMessageWindow
    index = battler.moves[@lastMove[idxBattler]] ? @lastMove[idxBattler] : 0
    @sprites["dataBox_#{idxBattler}"].selected = true
    B2W2.lower.open_moves(battler, index)
    loop do
      chosen = B2W2.lower.move
      next if chosen == -2 && !megaEvoPossible
      @lastMove[idxBattler] = chosen if chosen >= 0
      break if yield chosen
    end
    self.pbResetParams if @ret > -1
    B2W2.lower.close_later
    self.pbDeselectAll
  end

  # The bag in battle. What is done with the chosen item is the game's own (the party to use it on, the target
  # of a Poké Ball); leaving the party without choosing goes back to the command screen, as in White 2.
  alias b2w2_pbItemMenu pbItemMenu
  def pbItemMenu(idxBattler, firstAction, &block)
    return b2w2_pbItemMenu(idxBattler, firstAction, &block) if !B2W2.lower
    @idleTimer = -1
    @vector.reset
    @vector.inc = 0.2
    DualScreen.battle_menu(self) do
      B2W2.lower.blackout(true)
      bag = B2W2::BattleBag.new(self)
      loop do
        chosen = bag.choose
        break if !chosen
        item = GameData::Item.get(chosen)
        useType = item.battle_use
        used = false
        case useType
        when 1, 2, 3, 6, 7, 8   # on a Pokémon, one of its moves, or a battler
          alone = [1, 6].include?(useType) ? @battle.pbTeamLengthFromBattlerIndex(idxBattler) == 1 :
                  [3, 8].include?(useType) ? @battle.pbPlayerBattlerCount == 1 : false
          if alone
            used = yield item.id, useType, @battle.battlers[idxBattler].pokemonIndex, -1, bag
            next if !used
          else
            before = B2W2::BattleBag.memory.clone
            bag.remember
            bag.close
            bag = nil
            used = b2w2_item_on_party(idxBattler, item, useType, &block)
            B2W2::BattleBag.memory.update(before) if !used
          end
        when 4, 9   # on a foe: Poké Balls. With two foes the game's own rule refuses, as White 2 does.
          idxTarget = -1
          @battle.eachOtherSideBattler(idxBattler) { |b| idxTarget = b.index if idxTarget < 0 }
          used = yield item.id, useType, idxTarget, -1, bag
          next if !used
        when 5, 10   # no target
          used = yield item.id, useType, idxBattler, -1, bag
          next if !used
        end
        bag.remember if bag
        break
      end
      bag.close if bag
      B2W2.lower.blackout(false)
    end
  end

  # The game's party screen for an item that is used on a Pokémon; whether it was used
  def b2w2_item_on_party(idxBattler, item, useType)
    party = @battle.pbParty(idxBattler)
    partyPos = @battle.pbPartyOrder(idxBattler)
    partyStart, _partyEnd = @battle.pbTeamIndexRangeFromBattlerIndex(idxBattler)
    modParty = @battle.pbPlayerDisplayParty(idxBattler)
    pkmnScene = PokemonParty_Scene.new
    pkmnScreen = PokemonPartyScreen.new(pkmnScene, modParty)
    pkmnScreen.pbStartScene(_INTL("Use on which Pokémon?"), @battle.pbNumPositions(0, 0))
    used = false
    loop do
      pkmnScene.pbSetHelpText(_INTL("Use on which Pokémon?"))
      idxParty = pkmnScreen.pbChoosePokemon
      break if idxParty < 0
      idxPartyRet = partyPos.index(idxParty + partyStart)
      next if !idxPartyRet
      pkmn = party[idxPartyRet]
      next if !pkmn || pkmn.egg?
      idxMove = -1
      if useType == 2 || useType == 7
        idxMove = pkmnScreen.pbChooseMove(pkmn, _INTL("Restore which move?"))
        next if idxMove < 0
      end
      used = yield item.id, useType, idxPartyRet, idxMove, pkmnScene
      break if used
    end
    pkmnScene.pbEndScene
    return used
  end

  # The party opens below, so the battle stays in view above it and goes on moving
  alias dual_pbPartyScreen pbPartyScreen
  def pbPartyScreen(*args, &block)
    return dual_pbPartyScreen(*args, &block) if !DualScreen.on?
    DualScreen.battle_menu(self) { dual_pbPartyScreen(*args, &block) }
  end

  # (these hide and bring back the battle for such a screen)
  def pbFadeOutAndHide(sprites)
    return super if !DualScreen.battle_menu?
    return {}
  end

  def pbFadeInAndShow(sprites, visible = nil)
    return super if !DualScreen.battle_menu?
  end

  alias dual_animateScene animateScene
  def animateScene(*args, &block)
    @dual_animated = DualScreen.frame
    dual_animateScene(*args, &block)
  end

  # One frame of the battle's own motion, unless the battle has just moved itself
  def dual_animate
    animateScene(true) if @dual_animated != DualScreen.frame
  end
end

# The game's own command and move menus, which Safari battles still use
class CommandWindowEBDX
  alias dual_initialize initialize
  def initialize(viewport = nil, *args)
    dual_initialize(DualScreen.on? ? DualScreen.viewport : viewport, *args)
  end
end

class TargetWindowEBDX
  alias dual_initialize initialize
  def initialize(viewport = nil, *args)
    dual_initialize(DualScreen.on? ? DualScreen.viewport : viewport, *args)
  end
end

class FightWindowEBDX
  alias dual_initialize initialize
  def initialize(viewport = nil, *args)
    dual_initialize(DualScreen.on? ? DualScreen.viewport : viewport, *args)
    @background.visible = false if DualScreen.on?
  end
end

#===============================================================================
# The game's party screen, and the summary it leads to, when a battle opens them
#===============================================================================
class PokemonParty_Scene
  alias dual_pbStartScene pbStartScene
  def pbStartScene(*args)
    return dual_pbStartScene(*args) if !DualScreen.battle_menu?
    DualScreen.lower { dual_pbStartScene(*args) }
  end

  alias dual_pbChoosePokemon pbChoosePokemon
  def pbChoosePokemon(*args)
    @choosing = true
    return dual_pbChoosePokemon(*args)
  ensure
    @choosing = false
  end

  # A touch on a Pokémon or on Cancel chooses it
  alias dual_update update
  def update
    dual_update
    return if !@choosing || DualScreen.list_open?
    (Settings::MAX_PARTY_SIZE + ((@multiselect) ? 2 : 1)).times do |i|
      panel = @sprites["pokemon#{i}"]
      size = (i < Settings::MAX_PARTY_SIZE) ? [256, 98] : [112, 48]
      next if !panel || !DualScreen.touched_at?(@viewport, panel.x, panel.y, *size)
      pbSelect(i)
      DualScreen.press(Input::USE)
    end
  end
end

# Going from the party to the summary and back fades the lower screen only
alias dual_pbFadeOutIn pbFadeOutIn
def pbFadeOutIn(*args, &block)
  return dual_pbFadeOutIn(*args, &block) if !DualScreen.battle_menu?
  DualScreen.lower { dual_pbFadeOutIn(*args, &block) }
end

# The party opened in a battle fades in and out in the 6 frames White 2 takes, not the game's 24
module DualScreen
  FADE_FRAMES = 6

  def self.quick_fade(sprites, out)
    pbDeactivateWindows(sprites) do
      (0..FADE_FRAMES).each do |j|
        step = (out) ? j : FADE_FRAMES - j
        pbSetSpritesToColor(sprites, Color.new(0, 0, 0, step * 255 / FADE_FRAMES))
        (block_given?) ? yield : pbUpdateSpriteHash(sprites)
      end
    end
  end
end

alias dual_pbFadeOutAndHide pbFadeOutAndHide
def pbFadeOutAndHide(sprites, &block)
  return dual_pbFadeOutAndHide(sprites, &block) if !DualScreen.battle_menu?
  DualScreen.quick_fade(sprites, true, &block)
  visible = {}
  sprites.each do |key, sprite|
    next if !sprite || pbDisposed?(sprite)
    visible[key] = true if sprite.visible
    sprite.visible = false
  end
  return visible
end

alias dual_pbFadeInAndShow pbFadeInAndShow
def pbFadeInAndShow(sprites, visible = nil, &block)
  return dual_pbFadeInAndShow(sprites, visible, &block) if !DualScreen.battle_menu?
  if visible
    visible.each { |key, shown| sprites[key].visible = true if shown && sprites[key] && !pbDisposed?(sprites[key]) }
  end
  DualScreen.quick_fade(sprites, false, &block)
end

# A touch anywhere carries dialogue on, wherever it is shown
class Window_AdvancedTextPokemon
  alias dual_update update
  def update
    dual_update
    DualScreen.press(Input::USE) if self.letterbyletter && self.visible && DualScreen.tap && !DualScreen.list_open?
  end
end

# A touch on a choice of a list on the lower screen picks it
class SpriteWindow_Selectable
  alias dual_update update
  def update
    if self.active && self.visible && @item_max > 0 && @index >= 0 && !@ignore_input
      DualScreen.list_open
      tap = DualScreen.tap_in(self.viewport)
      if tap
        x = tap[0] - self.x - self.startX
        y = tap[1] - self.y - self.startY
        item = (self.top_item..self.top_item + self.page_item_max).find do |i|
          rect = itemRect(i)
          x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height
        end
        if item
          self.index = item
          DualScreen.press(Input::USE)
        end
      end
    end
    dual_update
  end
end
