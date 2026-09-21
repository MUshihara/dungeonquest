-- DQR universal macro place-context resolver.
-- Keeps recorded routes attached to dungeon rooms instead of brittle world XYZ.

local Context = {}

local CACHE_REFRESH = 5.00
local BOX_MARGIN = 10.0

local cache = {
    Dungeon = nil,
    At = -math.huge,
    Anchors = {},
    ByName = {},
}

local function dungeonName()
    local value = workspace:FindFirstChild("dungeonName")
    return value and tostring(value.Value) or ""
end

local function dungeon()
    return workspace:FindFirstChild("dungeon")
end

local function instanceAnchor(instance)
    if not instance then
        return nil
    end

    if instance:IsA("Model") then
        local okPivot, pivot = pcall(instance.GetPivot, instance)
        if okPivot then
            local okBox, boxCf, boxSize =
                pcall(instance.GetBoundingBox, instance)

            return {
                Instance = instance,
                Name = instance.Name,
                CFrame = pivot,
                BoxCFrame = okBox and boxCf or pivot,
                BoxSize = okBox and boxSize or Vector3.zero,
            }
        end
    end

    local part =
        instance:IsA("BasePart")
        and instance
        or instance:FindFirstChildWhichIsA("BasePart", true)

    if part then
        return {
            Instance = instance,
            Name = instance.Name,
            CFrame = part.CFrame,
            BoxCFrame = part.CFrame,
            BoxSize = part.Size,
        }
    end

    return nil
end

local function refresh(force)
    local current = dungeon()
    local now = os.clock()

    if not force
        and cache.Dungeon == current
        and now - cache.At < CACHE_REFRESH
    then
        return
    end

    cache.Dungeon = current
    cache.At = now
    cache.Anchors = {}
    cache.ByName = {}

    if not current then
        return
    end

    for _, child in ipairs(current:GetChildren()) do
        local anchor = instanceAnchor(child)

        if anchor then
            cache.Anchors[#cache.Anchors + 1] = anchor

            if not cache.ByName[anchor.Name] then
                cache.ByName[anchor.Name] = anchor
            end
        end
    end
end

local function boxScore(anchor, position)
    local boxCf = anchor.BoxCFrame
    local size = anchor.BoxSize

    if not boxCf or not size then
        return math.huge, false
    end

    local localPoint =
        boxCf:PointToObjectSpace(position)

    local half =
        size * 0.5
        + Vector3.new(
            BOX_MARGIN,
            BOX_MARGIN,
            BOX_MARGIN
        )

    local inside =
        math.abs(localPoint.X) <= half.X
        and math.abs(localPoint.Y) <= half.Y
        and math.abs(localPoint.Z) <= half.Z

    local pivotDistance =
        (position - anchor.CFrame.Position).Magnitude

    return pivotDistance, inside
end

local function bestAnchor(position)
    refresh(false)

    local bestInside
    local bestInsideDistance = math.huge
    local bestNear
    local bestNearDistance = math.huge

    for _, anchor in ipairs(cache.Anchors) do
        local distance, inside =
            boxScore(anchor, position)

        if inside and distance < bestInsideDistance then
            bestInside = anchor
            bestInsideDistance = distance
        end

        if distance < bestNearDistance then
            bestNear = anchor
            bestNearDistance = distance
        end
    end

    return bestInside or bestNear
end

local function packVector(v)
    return {v.X, v.Y, v.Z}
end

local function unpackVector(v)
    if type(v) ~= "table" or #v < 3 then
        return nil
    end

    return Vector3.new(
        tonumber(v[1]) or 0,
        tonumber(v[2]) or 0,
        tonumber(v[3]) or 0
    )
end

function Context.Environment()
    refresh(false)

    local roomNames = {}

    for _, anchor in ipairs(cache.Anchors) do
        roomNames[#roomNames + 1] = anchor.Name
    end

    table.sort(roomNames)

    return {
        UniverseId = game.GameId,
        PlaceId = game.PlaceId,
        DungeonName = dungeonName(),
        Rooms = roomNames,
    }
end

function Context.Validate(environment)
    if type(environment) ~= "table" then
        return true, "legacy_no_environment"
    end

    if environment.UniverseId
        and tonumber(environment.UniverseId)
            ~= tonumber(game.GameId)
    then
        return false, "different_universe"
    end

    local recordedDungeon =
        tostring(environment.DungeonName or "")

    local currentDungeon =
        dungeonName()

    if recordedDungeon ~= ""
        and recordedDungeon ~= currentDungeon
    then
        return false,
            "wrong_dungeon:"
            .. recordedDungeon
            .. "!="
            .. (
                currentDungeon ~= ""
                and currentDungeon
                or "none"
            )
    end

    -- If there is no dungeonName to disambiguate, require the exact place.
    if recordedDungeon == ""
        and environment.PlaceId
        and tonumber(environment.PlaceId)
            ~= tonumber(game.PlaceId)
    then
        return false, "wrong_place"
    end

    return true
end

function Context.Capture(position)
    position =
        typeof(position) == "Vector3"
        and position
        or Vector3.zero

    local result = {
        p = packVector(position),
    }

    local anchor =
        bestAnchor(position)

    if anchor then
        result.room = anchor.Name
        result.lp =
            packVector(
                anchor.CFrame
                    :PointToObjectSpace(position)
            )
    end

    return result
end

function Context.Resolve(point)
    if type(point) ~= "table" then
        return nil
    end

    refresh(false)

    local room =
        point.room
        and cache.ByName[tostring(point.room)]

    local localPosition =
        unpackVector(point.lp)

    if room and localPosition then
        return
            room.CFrame
                :PointToWorldSpace(localPosition)
    end

    return unpackVector(point.p)
end

function Context.RoomAt(position)
    local anchor =
        bestAnchor(position)

    return anchor and anchor.Name or nil
end

function Context.RoomOfInstance(instance)
    local currentDungeon = dungeon()

    if not currentDungeon or not instance then
        return nil
    end

    local current = instance

    while current
        and current ~= workspace
    do
        if current.Parent == currentDungeon then
            return current.Name
        end

        current = current.Parent
    end

    return nil
end

function Context.ResolveRoomCenter(roomName)
    refresh(false)

    local anchor =
        roomName
        and cache.ByName[tostring(roomName)]

    return anchor
        and anchor.CFrame.Position
        or nil
end

function Context.Refresh()
    refresh(true)
end

DQR_MACRO_CONTEXT = Context
