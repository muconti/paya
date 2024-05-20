-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
InAction = InAction or false -- Prevents the agent from taking multiple actions at once.
CurrentTarget = CurrentTarget or nil -- Store the current target
AttackCooldown = AttackCooldown or 0 -- Cooldown to prevent immediate re-attack

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

-- Checks if a given position is walkable (not an obstacle)
function isWalkable(x, y, obstacles)
    for _, obstacle in ipairs(obstacles) do
        if obstacle.x == x and obstacle.y == y then
            return false
        end
    end
    return true
end

-- Find the nearest power-up
function findNearestPowerUp(player, powerUps)
    local nearest = nil
    local minDist = math.huge
    for _, powerUp in ipairs(powerUps) do
        local dist = math.sqrt((player.x - powerUp.x)^2 + (player.y - powerUp.y)^2)
        if dist < minDist then
            nearest = powerUp
            minDist = dist
        end
    end
    return nearest
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

-- A* Pathfinding algorithm
function aStar(start, goal, obstacles)
    local openSet = {start}
    local cameFrom = {}
    local gScore = {[start] = 0}
    local fScore = {[start] = heuristicCostEstimate(start, goal)}

    while #openSet > 0 do
        local current = openSet[1]
        for i = 2, #openSet do
            if fScore[openSet[i]] < fScore[current] then
                current = openSet[i]
            end
        end

        if current.x == goal.x and current.y == goal.y then
            return reconstructPath(cameFrom, current)
        end

        table.remove(openSet, table.find(openSet, current))
        for _, neighbor in ipairs(getNeighbors(current, obstacles)) do
            local tentativeGScore = gScore[current] + distBetween(current, neighbor)
            if not gScore[neighbor] or tentativeGScore < gScore[neighbor] then
                cameFrom[neighbor] = current
                gScore[neighbor] = tentativeGScore
                fScore[neighbor] = gScore[neighbor] + heuristicCostEstimate(neighbor, goal)
                if not isInList(openSet, neighbor) then
                    table.insert(openSet, neighbor)
                end
            end
        end
    end

    return nil -- No path found
end

-- Heuristic cost estimate for A* 
function heuristicCostEstimate(start, goal)
    return math.abs(start.x - goal.x) + math.abs(start.y - goal.y)
end

-- Reconstruct path for A* from cameFrom map
function reconstructPath(cameFrom, current)
    local totalPath = {current}
    while cameFrom[current] do
        current = cameFrom[current]
        table.insert(totalPath, 1, current)
    end
    return totalPath
end

-- Get neighbors for A* considering obstacles
function getNeighbors(node, obstacles)
    local neighbors = {}
    local directions = {{1,0}, {0,1}, {-1,0}, {0,-1}}
    for _, dir in ipairs(directions) do
        local neighbor = {x = node.x + dir[1], y = node.y + dir[2]}
        if isWalkable(neighbor.x, neighbor.y, obstacles) then
            table.insert(neighbors, neighbor)
        end
    end
    return neighbors
end

-- Check if a node is in a list
function isInList(list, node)
    for _, n in ipairs(list) do
        if n.x == node.x and n.y == node.y then
            return true
        end
    end
    return false
end

-- Calculate distance between two nodes
function distBetween(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2)
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

-- Improved decision-making with aggressive strategy
function decideNextAction()
    local player = LatestGameState.Players[ao.id]
    local obstacles = LatestGameState.Obstacles
    local players = LatestGameState.Players

    -- Decrease attack cooldown
    if AttackCooldown > 0 then
        AttackCooldown = AttackCooldown - 1
    end

    -- Find the nearest opponent
    local nearestOpponent = findNearestOpponent(player, players)

    if nearestOpponent then
        -- If the opponent is in attack range, attack them
        if inRange(player.x, player.y, nearestOpponent.x, nearestOpponent.y, 1) and AttackCooldown <= 0 then
            print(colors.red .. "Attacking nearest opponent." .. colors.reset)
            ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(math.min(player.energy, nearestOpponent.energy + 1))})
            AttackCooldown = 2 -- Set a cooldown before the next attack
        else
            -- Move towards the nearest opponent
            print(colors.red .. "Moving towards nearest opponent." .. colors.reset)
            local path = aStar(player, nearestOpponent, obstacles)
            if path and #path > 1 then
                local nextStep = path[2]
                local direction = getDirection(player, nextStep)
                ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = direction})
            end
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
