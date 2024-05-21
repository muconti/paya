-- My PID = 0lf_Mae6Ogo_kXrSJGINK1NjwFoYRNns376iOCj-geA
-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
InAction = InAction or false -- Prevents the agent from taking multiple actions at once.
CurrentTarget = CurrentTarget or nil -- Store the current target
AttackCooldown = AttackCooldown or 0 -- Cooldown to prevent immediate re-attack
AttackCount = 0 -- Count of consecutive attacks on the current target
OpponentsAttacked = 0 -- Count of opponents attacked
IsResting = false -- Flag indicating if the bot is resting
RanAway = false -- Flag indicating if the bot has run away before resting

Logs = Logs or {}

colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
  Logs[msg] = Logs[msg] or {}
  table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Find the nearest opponent
function findNearestOpponent(player, players)
    local nearest = nil
    local minDist = math.huge
    for targetId, state in pairs(players) do
        if targetId ~= ao.id then
            local dist = math.sqrt((player.x - state.x)^2 + (player.y - state.y)^2)
            if dist < minDist then
                nearest = state
                minDist = dist
            end
        end
    end
    return nearest
end

-- Determine direction based on two positions
function getDirection(from, to)
    local dx = to.x - from.x
    local dy = to.y - from.y
    if dx > 0 and dy == 0 then
        return "Right"
    elseif dx < 0 and dy == 0 then
        return "Left"
    elseif dy > 0 and dx == 0 then
        return "Up"
    elseif dy < 0 and dx == 0 then
        return "Down"
    elseif dx > 0 and dy > 0 then
        return "UpRight"
    elseif dx < 0 and dy > 0 then
        return "UpLeft"
    elseif dx > 0 and dy < 0 then
        return "DownRight"
    elseif dx < 0 and dy < 0 then
        return "DownLeft"
    else
        return "Up" -- Default fallback
    end
end

-- Determine opposite direction
function getOppositeDirection(direction)
    local opposites = {
        Up = "Down",
        Down = "Up",
        Left = "Right",
        Right = "Left",
        UpRight = "DownLeft",
        UpLeft = "DownRight",
        DownRight = "UpLeft",
        DownLeft = "UpRight"
    }
    return opposites[direction]
end

-- Improved decision-making with aggressive strategy
function decideNextAction()
    local player = LatestGameState.Players[ao.id]
    local players = LatestGameState.Players

    -- Decrease attack cooldown
    if AttackCooldown > 0 then
        AttackCooldown = AttackCooldown - 1
    end

    -- Check if the bot needs to rest
    if IsResting then
        print(colors.blue .. "Resting to regain energy." .. colors.reset)
        if player.energy >= player.maxEnergy * 0.75 then
            IsResting = false
            RanAway = false
            print(colors.green .. "Energy sufficiently restored. Returning to attack." .. colors.reset)
        else
            ao.send({Target = Game, Action = "PlayerRest", Player = ao.id})
            InAction = false
            return
        end
    elseif player.energy < player.maxEnergy * 0.5 and not RanAway then
        local nearestOpponent = findNearestOpponent(player, players)
        if nearestOpponent then
            print(colors.blue .. "Energy below 50%. Running away from opponent." .. colors.reset)
            local direction = getOppositeDirection(getDirection(player, nearestOpponent))
            ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = direction})
            RanAway = true
            InAction = false
            return
        end
    elseif player.energy < player.maxEnergy * 0.5 then
        IsResting = true
        print(colors.blue .. "Energy below 50%. Going to rest." .. colors.reset)
        ao.send({Target = Game, Action = "PlayerRest", Player = ao.id})
        InAction = false
        return
    end

    -- Find the nearest opponent
    local nearestOpponent = findNearestOpponent(player, players)

    if nearestOpponent then
        -- If the opponent is in attack range, attack them
        if inRange(player.x, player.y, nearestOpponent.x, nearestOpponent.y, 1) and AttackCooldown <= 0 then
            AttackCount = AttackCount + 1
            print(colors.red .. "Attacking nearest opponent. Attack count: " .. AttackCount .. colors.reset)
            ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(math.min(player.energy, nearestOpponent.energy + 1))})
            AttackCooldown = 2 -- Set a cooldown before the next attack
            
            -- After 5 attacks, start dodging and circling
            if AttackCount >= 5 then
                AttackCount = 0
                print(colors.red .. "Dodging and circling opponent." .. colors.reset)
                local dodgeDirections = {"UpRight", "UpLeft", "DownRight", "DownLeft"}
                local bestDirection = dodgeDirections[math.random(#dodgeDirections)]
                ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = bestDirection})
            end
            
            -- Increase the count of opponents attacked after an attack
            if AttackCount == 1 then
                OpponentsAttacked = OpponentsAttacked + 1
            end
        else
            -- Move towards the nearest opponent
            print(colors.red .. "Moving towards nearest opponent." .. colors.reset)
            local direction = getDirection(player, nearestOpponent)
            ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = direction})
        end
        InAction = false
        return
    end

    -- Fallback to random movement if no opponent is found
    local directions = {"Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft"}
    local bestDirection = directions[math.random(#directions)]
    ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = bestDirection})
    InAction = false
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true -- InAction logic added
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then -- InAction logic added
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- Handler to trigger game state updates.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then -- InAction logic added
      InAction = true -- InAction logic added
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000"})
  end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print 'LatestGameState' for detailed view.")
  end
)

-- Handler to decide the next best action.
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then
      InAction = false -- InAction logic added
      return
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)

-- Handler to automatically attack when hit by another player.
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then -- InAction logic added
      InAction = true -- InAction logic added
      local playerEnergy = LatestGameState.Players[ao.id].energy
      if playerEnergy == nil then
        print(colors.red .. "Unable to read energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
      elseif playerEnergy == 0 then
        print(colors.red .. "Player has insufficient energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
      else
        print(colors.red .. "Returning attack." .. colors.reset)
        ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy)})
      end
      InAction = false -- InAction logic added
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)
