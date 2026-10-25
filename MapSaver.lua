--[[
    MAP SAVER v3 (Importação em etapas)

    1. Marque os 4 cantos da área (Setar 1 a 4) ou troque para "Mapa inteiro"
    2. Clique em "Salvar mapa"
    3. Clique em "Importar mapa" para recriar tudo em workspace.ImportedMap

    O que salva agora:
      Part, MeshPart, Wedge, CornerWedge, Truss, Seat, VehicleSeat, SpawnLocation,
      Model, Folder, Decal, Texture, SurfaceAppearance, SpecialMesh, luzes, Attachment,
      partículas, Beam, Trail, Fire, Smoke, Sounds, SurfaceGui/BillboardGui + UI,
      Welds, Values, ProximityPrompt, ClickDetector, Humanoid/NPC e mais.
    Qualquer outra classe criável é salva só com nome e hierarquia.

    Limitações do Roblox:
      - UnionOperation não pode ser recriada por script: vira Part (mesma posição/tamanho/cor).
      - Scripts, Terrain e Camera não são salvos.

    Bloqueio: só ficam de fora os nomes da lista (Car, Cars, Tree, Árvore...).
    A lista é editável no menu e muda por idioma (Ambos / Inglês / Português).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

if PlayerGui:FindFirstChild("MapSaverGui") then
    PlayerGui.MapSaverGui:Destroy()
end

for _, v in ipairs(workspace:GetChildren()) do
    if v.Name:match("^AreaMarker_") then
        v:Destroy()
    end
end

----------------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------------
local FILE_NAME = "SavedMap.lua"
local Y_BELOW = 100        -- quanto abaixo dos pontos ainda conta como dentro da área
local Y_ABOVE = 400        -- quanto acima dos pontos ainda conta como dentro da área
local CHUNK_SIZE = 40      -- instâncias por bloco no código gerado (reduz picos de carga)
local YIELD_EVERY = 100   -- pausa durante a leitura do mapa

local LANGS = {
    { "Ambos",     "Car, Cars, Carro, Carros, Tree, Trees, Árvore, Árvores" },
    { "Inglês",    "Car, Cars, Tree, Trees" },
    { "Português", "Carro, Carros, Árvore, Árvores" },
}

local state = {
    useArea = true,
    anchor = true,
    block = true,
    meshBlock = false,
    lang = 1,
    busy = false,
}

local positions = { nil, nil, nil, nil }
local markers = {}

----------------------------------------------------------------------
-- ÁREA
----------------------------------------------------------------------
local function getPlayerPosition()
    local char = LocalPlayer.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
    if not root then return nil end
    return root.Position
end

local function createMarker(pos, number)
    if markers[number] then
        markers[number]:Destroy()
    end

    local part = Instance.new("Part")
    part.Name = "AreaMarker_" .. number
    part.Size = Vector3.new(2.5, 2.5, 2.5)
    part.Shape = Enum.PartType.Ball
    part.Anchored = true
    part.CanCollide = false
    part.Material = Enum.Material.Neon
    part.Color = Color3.fromRGB(0, 255, 100)
    part.Position = pos + Vector3.new(0, 4, 0)
    part.Parent = workspace

    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 50, 0, 35)
    billboard.StudsOffset = Vector3.new(0, 3.5, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = part

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = tostring(number)
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0
    label.Font = Enum.Font.GothamBold
    label.TextSize = 22
    label.Parent = billboard

    markers[number] = part
end

local function clearMarkers()
    for _, marker in pairs(markers) do
        if marker then marker:Destroy() end
    end
    markers = {}
end

local function getAreaBounds()
    if not (positions[1] and positions[2] and positions[3] and positions[4]) then
        return nil
    end

    local p1, p2, p3, p4 = positions[1], positions[2], positions[3], positions[4]

    local minX = math.min(p1.X, p2.X, p3.X, p4.X)
    local maxX = math.max(p1.X, p2.X, p3.X, p4.X)
    local minZ = math.min(p1.Z, p2.Z, p3.Z, p4.Z)
    local maxZ = math.max(p1.Z, p2.Z, p3.Z, p4.Z)
    local minY = math.min(p1.Y, p2.Y, p3.Y, p4.Y) - Y_BELOW
    local maxY = math.max(p1.Y, p2.Y, p3.Y, p4.Y) + Y_ABOVE

    return {
        minX = minX, maxX = maxX,
        minZ = minZ, maxZ = maxZ,
        minY = minY, maxY = maxY,
        width = maxX - minX,
        length = maxZ - minZ,
    }
end

local function isInsideArea(pos, bounds)
    return pos.X >= bounds.minX and pos.X <= bounds.maxX
       and pos.Z >= bounds.minZ and pos.Z <= bounds.maxZ
       and pos.Y >= bounds.minY and pos.Y <= bounds.maxY
end

----------------------------------------------------------------------
-- PROPRIEDADES SALVAS POR CLASSE
----------------------------------------------------------------------
local function concat(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, k in ipairs(list) do
            out[#out + 1] = k
        end
    end
    return out
end

local PART_COMMON = {
    "Size", "CFrame", "Color", "Material", "MaterialVariant",
    "Transparency", "Reflectance", "CanCollide", "CanTouch", "CanQuery",
    "CastShadow", "Massless",
    "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface",
}

local GUI_COMMON = {
    "Size", "Position", "AnchorPoint", "BackgroundColor3", "BackgroundTransparency",
    "BorderSizePixel", "BorderColor3", "Visible", "ZIndex", "LayoutOrder",
    "ClipsDescendants", "Rotation", "AutomaticSize", "SizeConstraint",
}

local TEXT_PROPS = {
    "Text", "TextColor3", "TextSize", "FontFace", "TextScaled", "TextWrapped",
    "TextXAlignment", "TextYAlignment", "TextTransparency", "TextStrokeColor3",
    "TextStrokeTransparency", "RichText", "LineHeight", "TextTruncate",
}

local IMAGE_PROPS = {
    "Image", "ImageColor3", "ImageTransparency", "ScaleType", "SliceCenter",
    "ImageRectOffset", "ImageRectSize", "TileSize",
}

local LIGHT_PROPS = { "Brightness", "Color", "Range", "Shadows", "Enabled" }
local SPOT_PROPS = { "Brightness", "Color", "Range", "Angle", "Face", "Shadows", "Enabled" }
local WELD_PROPS = { "C0", "C1", "Enabled" }
local VALUE_PROPS = { "Value" }

local CLASS_PROPS = {
    -- Partes
    Part = concat({ "Shape" }, PART_COMMON),
    WedgePart = concat(PART_COMMON),
    CornerWedgePart = concat(PART_COMMON),
    TrussPart = concat({ "Style" }, PART_COMMON),
    MeshPart = concat({ "TextureID", "RenderFidelity", "CollisionFidelity", "DoubleSided" }, PART_COMMON),
    SpawnLocation = concat({ "Shape", "Neutral", "Duration", "AllowTeamChangeOnTouch", "TeamColor", "Enabled" }, PART_COMMON),
    Seat = concat({ "Shape", "Disabled" }, PART_COMMON),
    VehicleSeat = concat({ "Shape", "MaxSpeed", "Torque", "TurnSpeed", "HeadsUpDisplay", "Disabled" }, PART_COMMON),

    -- Containers
    Model = {},
    Folder = {},
    Tool = { "CanBeDropped", "Enabled", "ManualActivationOnly", "RequiresHandle", "ToolTip", "Grip" },
    Accessory = { "AttachmentPoint" },

    -- Visual / superfície
    Decal = { "Texture", "Color3", "Transparency", "Face", "ZIndex" },
    Texture = { "Texture", "Color3", "Transparency", "Face", "StudsPerTileU", "StudsPerTileV", "OffsetStudsU", "OffsetStudsV", "ZIndex" },
    SurfaceAppearance = { "ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap", "AlphaMode" },
    SpecialMesh = { "MeshId", "TextureId", "MeshType", "Scale", "Offset", "VertexColor" },
    BlockMesh = { "Scale", "Offset", "VertexColor" },
    CylinderMesh = { "Scale", "Offset", "VertexColor" },
    Highlight = { "FillColor", "FillTransparency", "OutlineColor", "OutlineTransparency", "DepthMode", "Enabled" },
    ForceField = { "Visible" },

    -- Luzes e efeitos
    PointLight = LIGHT_PROPS,
    SpotLight = SPOT_PROPS,
    SurfaceLight = SPOT_PROPS,
    Attachment = { "CFrame", "Visible" },
    ParticleEmitter = {
        "Texture", "Color", "Size", "Transparency", "Lifetime", "Rate", "Speed", "RotSpeed",
        "Rotation", "SpreadAngle", "Acceleration", "Drag", "EmissionDirection", "LightEmission",
        "LightInfluence", "ZOffset", "Orientation", "LockedToPart", "VelocityInheritance",
        "TimeScale", "Squash", "Enabled",
    },
    Beam = {
        "Color", "Transparency", "Width0", "Width1", "Segments", "LightEmission", "LightInfluence",
        "Texture", "TextureLength", "TextureSpeed", "TextureMode", "FaceCamera", "CurveSize0",
        "CurveSize1", "ZOffset", "Enabled",
    },
    Trail = {
        "Color", "Transparency", "Lifetime", "MinLength", "MaxLength", "LightEmission",
        "LightInfluence", "Texture", "TextureLength", "TextureMode", "FaceCamera", "WidthScale", "Enabled",
    },
    Fire = { "Color", "SecondaryColor", "Heat", "Size", "TimeScale", "Enabled" },
    Smoke = { "Color", "Opacity", "RiseVelocity", "Size", "TimeScale", "Enabled" },
    Sparkles = { "SparkleColor", "TimeScale", "Enabled" },
    Sound = { "SoundId", "Volume", "PlaybackSpeed", "Looped", "RollOffMode", "RollOffMinDistance", "RollOffMaxDistance", "Playing" },

    -- Interação
    ClickDetector = { "MaxActivationDistance" },
    ProximityPrompt = {
        "ActionText", "ObjectText", "HoldDuration", "MaxActivationDistance", "RequiresLineOfSight",
        "KeyboardKeyCode", "GamepadKeyCode", "Exclusivity", "UIOffset", "ClickablePrompt", "Enabled",
    },

    -- Joints
    Weld = WELD_PROPS,
    ManualWeld = WELD_PROPS,
    Motor6D = WELD_PROPS,
    Motor = concat(WELD_PROPS, { "MaxVelocity" }),
    WeldConstraint = { "Enabled" },

    -- NPC / personagem
    Humanoid = {
        "DisplayName", "MaxHealth", "Health", "WalkSpeed", "UseJumpPower", "JumpPower", "JumpHeight",
        "HipHeight", "RigType", "DisplayDistanceType", "NameDisplayDistance",
        "HealthDisplayDistance", "HealthDisplayType", "NameOcclusion",
    },
    BodyColors = { "HeadColor3", "TorsoColor3", "LeftArmColor3", "RightArmColor3", "LeftLegColor3", "RightLegColor3" },
    Shirt = { "ShirtTemplate", "Color3" },
    Pants = { "PantsTemplate", "Color3" },
    ShirtGraphic = { "Graphic", "Color3" },

    -- Values
    StringValue = VALUE_PROPS,
    IntValue = VALUE_PROPS,
    NumberValue = VALUE_PROPS,
    BoolValue = VALUE_PROPS,
    Color3Value = VALUE_PROPS,
    Vector3Value = VALUE_PROPS,
    CFrameValue = VALUE_PROPS,
    BrickColorValue = VALUE_PROPS,
    ObjectValue = {},

    -- GUI em placas e letreiros
    SurfaceGui = {
        "Face", "SizingMode", "CanvasSize", "PixelsPerStud", "LightInfluence", "Brightness",
        "AlwaysOnTop", "Enabled", "ResetOnSpawn", "ZOffset", "MaxDistance", "ClipsDescendants", "ZIndexBehavior",
    },
    BillboardGui = {
        "Size", "StudsOffset", "ExtentsOffset", "SizeOffset", "StudsOffsetWorldSpace", "AlwaysOnTop",
        "MaxDistance", "LightInfluence", "Enabled", "ResetOnSpawn", "Active", "Brightness",
        "ClipsDescendants", "ZIndexBehavior",
    },
    Frame = concat(GUI_COMMON),
    ScrollingFrame = concat(GUI_COMMON, { "CanvasSize", "ScrollBarThickness", "ScrollingDirection" }),
    TextLabel = concat(GUI_COMMON, TEXT_PROPS),
    TextButton = concat(GUI_COMMON, TEXT_PROPS, { "AutoButtonColor" }),
    ImageLabel = concat(GUI_COMMON, IMAGE_PROPS),
    ImageButton = concat(GUI_COMMON, IMAGE_PROPS, { "AutoButtonColor" }),
    UICorner = { "CornerRadius" },
    UIStroke = { "Color", "Thickness", "Transparency", "ApplyStrokeMode", "LineJoinMode", "Enabled" },
    UIGradient = { "Color", "Transparency", "Rotation", "Offset", "Enabled" },
    UIListLayout = { "Padding", "FillDirection", "HorizontalAlignment", "VerticalAlignment", "SortOrder" },
    UIGridLayout = {
        "CellPadding", "CellSize", "FillDirection", "FillDirectionMaxCells",
        "HorizontalAlignment", "VerticalAlignment", "SortOrder", "StartCorner",
    },
    UIPadding = { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" },
    UIAspectRatioConstraint = { "AspectRatio", "AspectType", "DominantAxis" },
    UIScale = { "Scale" },
    UISizeConstraint = { "MaxSize", "MinSize" },
}

-- Propriedades que apontam para outra instância (resolvidas no fim)
local REF_PROPS = {
    Model = { "PrimaryPart" },
    Weld = { "Part0", "Part1" },
    ManualWeld = { "Part0", "Part1" },
    Motor6D = { "Part0", "Part1" },
    Motor = { "Part0", "Part1" },
    WeldConstraint = { "Part0", "Part1" },
    Beam = { "Attachment0", "Attachment1" },
    Trail = { "Attachment0", "Attachment1" },
    ObjectValue = { "Value" },
}

-- Classes que nunca são salvas (nem os filhos)
local SKIP_CLASSES = {
    Camera = true,
    Terrain = true,
    Script = true,
    LocalScript = true,
    ModuleScript = true,
    NegateOperation = true,
}

-- Sempre salva, sem comparar com o valor padrão (só vale para Parts)
local ALWAYS_SAVE = { Size = true, CFrame = true }

----------------------------------------------------------------------
-- SERIALIZER
----------------------------------------------------------------------
local function readProp(obj, key)
    return obj[key]
end

local function num(n, decimals)
    if n ~= n or n == math.huge or n == -math.huge then
        return "0"
    end
    local s = string.format("%." .. (decimals or 4) .. "f", n)
    if s:find("%.") then
        s = s:gsub("0+$", "")
        s = s:gsub("%.$", "")
    end
    if s == "-0" or s == "" then
        s = "0"
    end
    return s
end

local function nearly(a, b)
    return math.abs(a - b) < 0.00001
end

local function serializeCFrame(cf)
    local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()

    local identity = nearly(r00, 1) and nearly(r11, 1) and nearly(r22, 1)
        and nearly(r01, 0) and nearly(r02, 0) and nearly(r10, 0)
        and nearly(r12, 0) and nearly(r20, 0) and nearly(r21, 0)

    if identity then
        return string.format("CFrame.new(%s,%s,%s)", num(x), num(y), num(z))
    end

    return string.format(
        "CFrame.new(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
        num(x), num(y), num(z),
        num(r00, 6), num(r01, 6), num(r02, 6),
        num(r10, 6), num(r11, 6), num(r12, 6),
        num(r20, 6), num(r21, 6), num(r22, 6)
    )
end

local function serializeColor3(c)
    local r, g, b = c.R * 255, c.G * 255, c.B * 255
    local function isWhole(x)
        return math.abs(x - math.floor(x + 0.5)) < 0.02
    end
    if isWhole(r) and isWhole(g) and isWhole(b) then
        return string.format("Color3.fromRGB(%d,%d,%d)", math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5))
    end
    return string.format("Color3.new(%s,%s,%s)", num(c.R, 5), num(c.G, 5), num(c.B, 5))
end

local function serializeValue(v)
    local t = typeof(v)

    if t == "number" then
        return num(v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "Vector3" then
        return string.format("Vector3.new(%s,%s,%s)", num(v.X), num(v.Y), num(v.Z))
    elseif t == "Vector2" then
        return string.format("Vector2.new(%s,%s)", num(v.X), num(v.Y))
    elseif t == "CFrame" then
        return serializeCFrame(v)
    elseif t == "Color3" then
        return serializeColor3(v)
    elseif t == "EnumItem" then
        return string.format("Enum.%s[%q]", tostring(v.EnumType), v.Name)
    elseif t == "UDim2" then
        return string.format("UDim2.new(%s,%s,%s,%s)", num(v.X.Scale), num(v.X.Offset), num(v.Y.Scale), num(v.Y.Offset))
    elseif t == "UDim" then
        return string.format("UDim.new(%s,%s)", num(v.Scale), num(v.Offset))
    elseif t == "BrickColor" then
        return string.format("BrickColor.new(%d)", v.Number)
    elseif t == "NumberRange" then
        return string.format("NumberRange.new(%s,%s)", num(v.Min), num(v.Max))
    elseif t == "NumberSequence" then
        local pts = {}
        for _, k in ipairs(v.Keypoints) do
            pts[#pts + 1] = string.format("NumberSequenceKeypoint.new(%s,%s,%s)", num(k.Time), num(k.Value), num(k.Envelope))
        end
        return "NumberSequence.new({" .. table.concat(pts, ",") .. "})"
    elseif t == "ColorSequence" then
        local pts = {}
        for _, k in ipairs(v.Keypoints) do
            pts[#pts + 1] = string.format("ColorSequenceKeypoint.new(%s,%s)", num(k.Time), serializeColor3(k.Value))
        end
        return "ColorSequence.new({" .. table.concat(pts, ",") .. "})"
    elseif t == "Rect" then
        return string.format("Rect.new(%s,%s,%s,%s)", num(v.Min.X), num(v.Min.Y), num(v.Max.X), num(v.Max.Y))
    elseif t == "Font" then
        return string.format("Font.new(%q,Enum.FontWeight[%q],Enum.FontStyle[%q])", v.Family, v.Weight.Name, v.Style.Name)
    end

    return nil
end

----------------------------------------------------------------------
-- BLOQUEIO POR NOME (Car, Cars, Tree, Árvore...)
----------------------------------------------------------------------
local ACCENTS = {
    ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a",
    ["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ã"] = "a", ["Ä"] = "a",
    ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
    ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
    ["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i",
    ["Í"] = "i", ["Ì"] = "i", ["Î"] = "i", ["Ï"] = "i",
    ["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o",
    ["Ó"] = "o", ["Ò"] = "o", ["Ô"] = "o", ["Õ"] = "o", ["Ö"] = "o",
    ["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u",
    ["Ú"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u",
    ["ç"] = "c", ["Ç"] = "c",
}

-- minúsculo, sem acento, sem número no final: "Árvore 3" -> "arvore", "Tree_12" -> "tree"
local function normalizeName(s)
    s = tostring(s)
    if s:find("[\128-\255]") then
        for k, v in pairs(ACCENTS) do
            s = s:gsub(k, v)
        end
    end
    s = s:lower()
    s = s:gsub("%(%d+%)", "")
    s = s:gsub("[%s_%-%d%.]+$", "")
    s = s:gsub("^[%s_%-]+", "")
    return s
end

local function parseBlocked(text)
    local set = {}
    for item in tostring(text):gmatch("[^,;\n]+") do
        local n = normalizeName(item)
        if n ~= "" then
            set[n] = true
        end
    end
    return set
end

----------------------------------------------------------------------
-- VALORES PADRÃO (só salva o que for diferente do padrão da classe)
----------------------------------------------------------------------
local defaultInstances = {}
local defaultSer = {}

local function getDefaultInstance(class)
    local d = defaultInstances[class]
    if d == nil then
        local ok, inst = pcall(Instance.new, class)
        if ok and inst then
            d = inst
        else
            d = false
        end
        defaultInstances[class] = d
    end
    return d
end

local function getDefaultSer(class, prop)
    local byClass = defaultSer[class]
    if not byClass then
        byClass = {}
        defaultSer[class] = byClass
    end

    local cached = byClass[prop]
    if cached == nil then
        cached = false
        local def = getDefaultInstance(class)
        if def then
            local ok, v = pcall(readProp, def, prop)
            if ok and v ~= nil then
                cached = serializeValue(v) or false
            end
        end
        byClass[prop] = cached
    end
    return cached
end

local function destroyDefaults()
    for _, inst in pairs(defaultInstances) do
        if inst then
            pcall(function() inst:Destroy() end)
        end
    end
    defaultInstances = {}
    defaultSer = {}
end

----------------------------------------------------------------------
-- GERADOR DO CÓDIGO SALVO
----------------------------------------------------------------------
local HEADER = [==[
-- Mapa salvo pelo MapSaver v3
local o = {}
local root = Instance.new("Folder")
root.Name = "ImportedMap"
root.Parent = workspace
o[0] = root

local stat = { made = 0, fail = 0, meshReal = 0, meshFallback = 0 }
local function set(i, k, v) i[k] = v end
local function W() task.wait() end

-- 1) tenta MeshPart de verdade (precisa que o executor deixe setar MeshId)
-- 2) se não der, usa Part + SpecialMesh (funciona em qualquer lugar)
local function newMesh(meshId, meshScale)
    local ok, mp = pcall(Instance.new, "MeshPart")
    if ok and mp then
        if meshId ~= "" then pcall(set, mp, "MeshId", meshId) end
        if mp.MeshId ~= "" then
            stat.meshReal = stat.meshReal + 1
            return mp, false, nil
        end
        mp:Destroy()
    end

    local part = Instance.new("Part")
    local sm = Instance.new("SpecialMesh")
    sm.MeshType = Enum.MeshType.FileMesh
    pcall(set, sm, "MeshId", meshId)
    sm.Scale = meshScale or Vector3.new(1, 1, 1)
    sm.Parent = part
    stat.meshFallback = stat.meshFallback + 1
    return part, true, sm
end

local function I(class, name, parent, props, meshId, meshScale)
    local inst, isFallback, sm
    if class == "MeshPart" then
        inst, isFallback, sm = newMesh(meshId or "", meshScale)
    else
        local ok, r = pcall(Instance.new, class)
        if not ok or not r then
            stat.fail = stat.fail + 1
            return nil
        end
        inst = r
    end
    inst.Name = name
    if props then
        for n = 1, #props, 2 do
            local k, v = props[n], props[n + 1]
            if isFallback then
                if k == "TextureID" then
                    pcall(set, sm, "TextureId", v)
                elseif k ~= "RenderFidelity" and k ~= "CollisionFidelity" and k ~= "DoubleSided" then
                    pcall(set, inst, k, v)
                end
            else
                pcall(set, inst, k, v)
            end
        end
    end
    inst.Parent = parent
    stat.made = stat.made + 1

    -- Importa em lotes menores para reduzir picos de processamento no Studio Lite.
    if stat.made % 25 == 0 then
        task.wait()
    end

    return inst
end

local function R(a, k, b)
    if o[a] and o[b] then pcall(set, o[a], k, o[b]) end
end

]==]

local function generateSaveCode(bounds, opts, progress)
    local useArea = opts.useArea
    local forceAnchor = opts.forceAnchor
    local blocking = opts.blocking
    local blockedSet = opts.blockedSet

    local buf = {}
    local index = 0
    local inChunk = false
    local chunkLines = 0
    local idOf = {}
    local refs = {}
    local stats = { blocked = 0, converted = 0, meshBlock = 0 }
    local ticks = 0
    local scanTicks = 0
    local scanHas, scanIn = {}, {}
    local blockedCache = {}

    local function emit(line)
        if not inChunk then
            buf[#buf + 1] = "do local c=function()"
            inChunk = true
            chunkLines = 0
        end
        buf[#buf + 1] = line
        chunkLines = chunkLines + 1
        if chunkLines >= CHUNK_SIZE then
            buf[#buf + 1] = "end c() W() end"
            inChunk = false
        end
    end

    local function flush()
        if inChunk then
            buf[#buf + 1] = "end c() W() end"
            inChunk = false
        end
    end

    local function isBlocked(name)
        if not blocking then return false end
        local cached = blockedCache[name]
        if cached == nil then
            cached = blockedSet[normalizeName(name)] == true
            blockedCache[name] = cached
        end
        return cached
    end

    -- Retorna: (tem alguma BasePart dentro, tem alguma BasePart dentro da área)
    local function scan(obj)
        local cached = scanHas[obj]
        if cached ~= nil then
            return cached, scanIn[obj]
        end

        scanTicks = scanTicks + 1
        if scanTicks % 3000 == 0 then
            task.wait()
        end

        local has, ins = false, false
        if obj:IsA("BasePart") then
            has = true
            ins = isInsideArea(obj.Position, bounds)
        end

        for _, child in ipairs(obj:GetChildren()) do
            if not SKIP_CLASSES[child.ClassName] and not isBlocked(child.Name) then
                local h, i = scan(child)
                if h then has = true end
                if i then ins = true end
            end
        end

        scanHas[obj] = has
        scanIn[obj] = ins
        return has, ins
    end

    local function keep(obj, depth)
        if not useArea then return true end

        if obj:IsA("BasePart") then
            return isInsideArea(obj.Position, bounds)
        end

        local has, ins = scan(obj)
        if has then return ins end

        -- sem posição própria (Sound, Value, etc.): só vai junto se o pai foi salvo
        return depth > 0
    end

    local function buildProps(obj, class, isPart)
        local list = CLASS_PROPS[class]
        local out = {}
        local noSkip = (class == "MeshPart")

        if list then
            for _, k in ipairs(list) do
                local ok, v = pcall(readProp, obj, k)
                if ok and v ~= nil then
                    local s = serializeValue(v)
                    if s then
                        if noSkip or (isPart and ALWAYS_SAVE[k]) or s ~= getDefaultSer(class, k) then
                            out[#out + 1] = string.format("%q,%s", k, s)
                        end
                    end
                end
            end
        end

        if isPart then
            if forceAnchor or obj.Anchored then
                out[#out + 1] = '"Anchored",true'
            end
        end

        if #out == 0 then
            return "nil"
        end
        return "{" .. table.concat(out, ",") .. "}"
    end

    local function process(obj, parentIdx, depth)
        ticks = ticks + 1
        if ticks % YIELD_EVERY == 0 then
            if progress then progress(index) end
            task.wait()
        end

        local cn = obj.ClassName
        if SKIP_CLASSES[cn] then
            return
        end

        if isBlocked(obj.Name) then
            stats.blocked = stats.blocked + 1
            return
        end

        if not keep(obj, depth) then
            return
        end

        local isPart = obj:IsA("BasePart")
        local saveClass = cn
        if isPart and not CLASS_PROPS[cn] then
            -- UnionOperation e similares não podem ser criadas por script
            saveClass = "Part"
            stats.converted = stats.converted + 1
        elseif cn == "MeshPart" and opts.meshAsBlock then
            saveClass = "Part"
            stats.meshBlock = stats.meshBlock + 1
        end

        if not getDefaultInstance(saveClass) then
            -- classe que não dá pra criar (ex: TouchTransmitter): pula ela e segue nos filhos
            for _, child in ipairs(obj:GetChildren()) do
                process(child, parentIdx, depth)
            end
            return
        end

        index = index + 1
        local myIdx = index
        idOf[obj] = myIdx

        local propStr = buildProps(obj, saveClass, isPart)

        local meshArg = ""
        if saveClass == "MeshPart" then
            local ok, mid = pcall(readProp, obj, "MeshId")
            if ok and type(mid) == "string" and mid ~= "" then
                local scale = Vector3.new(1, 1, 1)
                local okSize, size = pcall(readProp, obj, "Size")
                local okMesh, meshSize = pcall(readProp, obj, "MeshSize")
                if okSize and okMesh and typeof(size) == "Vector3" and typeof(meshSize) == "Vector3"
                    and meshSize.X > 0 and meshSize.Y > 0 and meshSize.Z > 0 then
                    scale = Vector3.new(size.X / meshSize.X, size.Y / meshSize.Y, size.Z / meshSize.Z)
                end
                meshArg = string.format(",%q,%s", mid, serializeValue(scale))
            end
        end

        emit(string.format("o[%d]=I(%q,%q,o[%d],%s%s)", myIdx, saveClass, obj.Name, parentIdx, propStr, meshArg))

        local refList = REF_PROPS[saveClass]
        if refList then
            for _, k in ipairs(refList) do
                local ok, target = pcall(readProp, obj, k)
                if ok and typeof(target) == "Instance" then
                    refs[#refs + 1] = { myIdx, k, target }
                end
            end
        end

        for _, child in ipairs(obj:GetChildren()) do
            process(child, myIdx, depth + 1)
        end
    end

    for _, child in ipairs(workspace:GetChildren()) do
        local skip = child.Name == "Camera"
            or child:IsA("Terrain")
            or child.Name:match("^AreaMarker_") ~= nil
            or Players:GetPlayerFromCharacter(child) ~= nil

        if not skip then
            process(child, 0, 0)
        end
    end

    for _, r in ipairs(refs) do
        local targetIdx = idOf[r[3]]
        if targetIdx then
            emit(string.format("R(%d,%q,%d)", r[1], r[2], targetIdx))
        end
    end
    flush()

    buf[#buf + 1] = string.format(
        'print("[MapSaver] Importado: "..stat.made.." de %d objetos | MeshParts reais: "..stat.meshReal.." | via SpecialMesh: "..stat.meshFallback.." | falhas: "..stat.fail)\nreturn stat',
        index
    )

    destroyDefaults()

    return HEADER .. table.concat(buf, "\n") .. "\n", index, stats
end

----------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------
local C = {
    bg = Color3.fromRGB(25, 25, 30),
    header = Color3.fromRGB(40, 40, 50),
    field = Color3.fromRGB(35, 35, 45),
    blue = Color3.fromRGB(50, 120, 220),
    green = Color3.fromRGB(40, 180, 80),
    toggleOn = Color3.fromRGB(40, 150, 80),
    red = Color3.fromRGB(200, 50, 50),
    grey = Color3.fromRGB(80, 80, 90),
    mode = Color3.fromRGB(70, 70, 105),
    text = Color3.fromRGB(255, 255, 255),
    dim = Color3.fromRGB(200, 200, 200),
}

local MAIN_W = 280
local HEADER_H = 36
local STATUS_H = 60

local viewportY = 600
if workspace.CurrentCamera then
    viewportY = workspace.CurrentCamera.ViewportSize.Y
end
local MAIN_H = math.clamp(viewportY - 60, 260, 470)

local function addCorner(inst, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = inst
    return c
end

local function newButton(parent, text, color, height, order, textSize)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, height)
    b.BackgroundColor3 = color
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = C.text
    b.Font = Enum.Font.GothamBold
    b.TextSize = textSize or 14
    b.LayoutOrder = order
    b.Parent = parent
    addCorner(b, 8)
    return b
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MapSaverGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 999
ScreenGui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, MAIN_W, 0, MAIN_H)
Main.Position = UDim2.new(0.02, 0, 0.06, 0)
Main.BackgroundColor3 = C.bg
Main.BorderSizePixel = 0
Main.Active = true
Main.ClipsDescendants = true
Main.Parent = ScreenGui
addCorner(Main, 12)

-- Cabeçalho (arrastável)
local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, HEADER_H)
Header.BackgroundColor3 = C.header
Header.BorderSizePixel = 0
Header.Parent = Main
addCorner(Header, 12)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -80, 1, 0)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "Map Saver v2"
Title.TextColor3 = C.text
Title.Font = Enum.Font.GothamBold
Title.TextSize = 16
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 28, 0, 24)
MinBtn.Position = UDim2.new(1, -66, 0, 6)
MinBtn.BackgroundColor3 = C.grey
MinBtn.BorderSizePixel = 0
MinBtn.Text = "-"
MinBtn.TextColor3 = C.text
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 16
MinBtn.Parent = Header
addCorner(MinBtn, 6)

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 28, 0, 24)
CloseBtn.Position = UDim2.new(1, -34, 0, 6)
CloseBtn.BackgroundColor3 = C.red
CloseBtn.BorderSizePixel = 0
CloseBtn.Text = "X"
CloseBtn.TextColor3 = C.text
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 14
CloseBtn.Parent = Header
addCorner(CloseBtn, 6)

-- Status (sempre visível)
local Status = Instance.new("TextLabel")
Status.Name = "Status"
Status.Size = UDim2.new(1, -20, 0, STATUS_H - 6)
Status.Position = UDim2.new(0, 10, 0, HEADER_H + 6)
Status.BackgroundColor3 = C.field
Status.BorderSizePixel = 0
Status.Text = "Marque os 4 cantos da área"
Status.TextColor3 = C.dim
Status.Font = Enum.Font.Gotham
Status.TextSize = 12
Status.TextWrapped = true
Status.Parent = Main
addCorner(Status, 7)

-- Corpo com rolagem
local BODY_TOP = HEADER_H + STATUS_H + 6

local Body = Instance.new("ScrollingFrame")
Body.Name = "Body"
Body.Size = UDim2.new(1, 0, 1, -BODY_TOP)
Body.Position = UDim2.new(0, 0, 0, BODY_TOP)
Body.BackgroundTransparency = 1
Body.BorderSizePixel = 0
Body.ScrollBarThickness = 3
Body.CanvasSize = UDim2.new(0, 0, 0, 0)
Body.AutomaticCanvasSize = Enum.AutomaticSize.Y
Body.ScrollingDirection = Enum.ScrollingDirection.Y
Body.Parent = Main

local BodyList = Instance.new("UIListLayout")
BodyList.Padding = UDim.new(0, 6)
BodyList.SortOrder = Enum.SortOrder.LayoutOrder
BodyList.Parent = Body

local BodyPad = Instance.new("UIPadding")
BodyPad.PaddingTop = UDim.new(0, 2)
BodyPad.PaddingBottom = UDim.new(0, 10)
BodyPad.PaddingLeft = UDim.new(0, 10)
BodyPad.PaddingRight = UDim.new(0, 12)
BodyPad.Parent = Body

-- 1) Cantos da área (grade 2x2)
local CornerGrid = Instance.new("Frame")
CornerGrid.Size = UDim2.new(1, 0, 0, 66)
CornerGrid.BackgroundTransparency = 1
CornerGrid.LayoutOrder = 1
CornerGrid.Parent = Body

local Grid = Instance.new("UIGridLayout")
Grid.CellSize = UDim2.new(0.5, -3, 0, 30)
Grid.CellPadding = UDim2.new(0, 6, 0, 6)
Grid.SortOrder = Enum.SortOrder.LayoutOrder
Grid.Parent = CornerGrid

local cornerBtns = {}
for i = 1, 4 do
    local b = Instance.new("TextButton")
    b.BackgroundColor3 = C.blue
    b.BorderSizePixel = 0
    b.Text = "Setar " .. i
    b.TextColor3 = C.text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.LayoutOrder = i
    b.Parent = CornerGrid
    addCorner(b, 7)
    cornerBtns[i] = b
end

-- 2) Opções
local ModeBtn = newButton(Body, "Modo: Área marcada", C.mode, 30, 2, 13)
local AnchorBtn = newButton(Body, "", C.toggleOn, 30, 3, 13)
local MeshBtn = newButton(Body, "", C.mode, 30, 4, 13)
local BlockBtn = newButton(Body, "", C.toggleOn, 30, 5, 13)
local LangBtn = newButton(Body, "", C.mode, 30, 6, 13)

local NamesBox = Instance.new("TextBox")
NamesBox.Size = UDim2.new(1, 0, 0, 34)
NamesBox.BackgroundColor3 = C.field
NamesBox.BorderSizePixel = 0
NamesBox.Text = LANGS[1][2]
NamesBox.PlaceholderText = "nomes bloqueados, separados por vírgula"
NamesBox.TextColor3 = C.text
NamesBox.PlaceholderColor3 = Color3.fromRGB(140, 140, 150)
NamesBox.Font = Enum.Font.Gotham
NamesBox.TextSize = 12
NamesBox.TextWrapped = true
NamesBox.ClearTextOnFocus = false
NamesBox.LayoutOrder = 7
NamesBox.Parent = Body
addCorner(NamesBox, 7)

-- 3) Ações
local SaveBtn = newButton(Body, "Salvar mapa", C.green, 36, 8, 15)
local ImportBtn = newButton(Body, "Importar mapa", C.red, 36, 9, 15)
local ClearBtn = newButton(Body, "Limpar marcadores", C.grey, 30, 10, 13)

----------------------------------------------------------------------
-- LÓGICA DA GUI
----------------------------------------------------------------------
local function setStatus(text)
    Status.Text = text
end

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 4,
        })
    end)
end

local function refreshToggle(btn, label, on)
    btn.Text = label .. (on and ": ON" or ": OFF")
    btn.BackgroundColor3 = on and C.toggleOn or C.grey
end

local function refreshOptions()
    ModeBtn.Text = state.useArea and "Modo: Área marcada" or "Modo: Mapa inteiro"
    refreshToggle(AnchorBtn, "Ancorar tudo", state.anchor)
    MeshBtn.Text = state.meshBlock and "MeshParts: só bloco (sem mesh)" or "MeshParts: com mesh"
    refreshToggle(BlockBtn, "Bloquear carros/árvores", state.block)
    LangBtn.Text = "Idioma do bloqueio: " .. LANGS[state.lang][1]
end

local function countPoints()
    local count = 0
    for i = 1, 4 do
        if positions[i] then count = count + 1 end
    end
    return count
end

local function refreshAreaStatus()
    if not state.useArea then
        setStatus("Modo mapa inteiro: salva todo o Workspace")
        return
    end

    local bounds = getAreaBounds()
    if bounds then
        setStatus(string.format("Área: %.0f x %.0f studs", bounds.width, bounds.length))
    elseif countPoints() == 0 then
        setStatus("Marque os 4 cantos da área")
    else
        setStatus("Pontos marcados: " .. countPoints() .. "/4")
    end
end

local function setPosition(number)
    local pos = getPlayerPosition()
    if not pos then
        setStatus("Personagem não encontrado")
        return
    end

    positions[number] = pos
    createMarker(pos, number)

    cornerBtns[number].BackgroundColor3 = C.green
    cornerBtns[number].Text = "Setar " .. number .. " ✓"

    refreshAreaStatus()
end

local function salvarMapa()
    if state.busy then return end

    local bounds = nil
    if state.useArea then
        bounds = getAreaBounds()
        if not bounds then
            setStatus("Marque os 4 pontos primeiro!")
            notify("MapSaver", "Marque os 4 pontos primeiro!", 4)
            return
        end
    end

    local opts = {
        useArea = state.useArea,
        forceAnchor = state.anchor,
        blocking = state.block,
        meshAsBlock = state.meshBlock,
        blockedSet = parseBlocked(NamesBox.Text),
    }

    state.busy = true
    setStatus("Lendo o mapa...")

    task.spawn(function()
        local ok, err = pcall(function()
            local code, count, stats = generateSaveCode(bounds, opts, function(n)
                setStatus("Lendo... " .. n .. " objetos")
            end)

            if count == 0 then
                error("Nada para salvar (área vazia ou tudo bloqueado)")
            end

            local info = string.format("%d objetos | %.0f KB", count, #code / 1024)
            if stats.blocked > 0 then
                info = info .. " | " .. stats.blocked .. " bloqueados"
            end
            if stats.converted > 0 then
                info = info .. " | " .. stats.converted .. " unions viraram Part"
            end
            if stats.meshBlock > 0 then
                info = info .. " | " .. stats.meshBlock .. " meshes viraram bloco"
            end

            if writefile then
                writefile(FILE_NAME, code)
                setStatus("Salvo! " .. info)
                notify("MapSaver", "Salvo! (" .. count .. " objetos)", 5)
            elseif setclipboard then
                setclipboard(code)
                setStatus("Copiado para o clipboard! " .. info)
                notify("MapSaver", "Copiado para clipboard!", 4)
            else
                error("Executor sem writefile e sem setclipboard")
            end
        end)

        state.busy = false

        if not ok then
            warn("[MapSaver] Erro ao salvar:", err)
            setStatus("Erro ao salvar: " .. tostring(err))
            notify("Erro ao salvar", tostring(err), 6)
        end
    end)
end

local function importarMapa()
    if state.busy then return end

    state.busy = true
    setStatus("Importando...")

    task.spawn(function()
        local summary
        local ok, err = pcall(function()
            local code

            if isfile and isfile(FILE_NAME) then
                code = readfile(FILE_NAME)
            elseif getclipboard then
                code = getclipboard()
            else
                error("Nenhum mapa encontrado")
            end

            if not code or #code < 50 then
                error("Código inválido ou vazio")
            end

            if not loadstring then
                error("Executor sem loadstring")
            end

            local func, loadErr = loadstring(code)
            if not func then
                error("Erro ao carregar código: " .. tostring(loadErr))
            end

            local old = workspace:FindFirstChild("ImportedMap")
            if old then old:Destroy() end

            summary = func()
        end)

        state.busy = false

        if ok then
            local msg = "Mapa importado em workspace.ImportedMap"
            if type(summary) == "table" then
                msg = string.format(
                    "Importado: %d objetos | meshes: %d reais, %d via SpecialMesh | falhas: %d",
                    summary.made, summary.meshReal, summary.meshFallback, summary.fail
                )
                if summary.meshFallback > 0 then
                    msg = msg .. " | meshes invisíveis? Salve com 'MeshParts: só bloco'"
                end
            end
            setStatus(msg)
            notify("MapSaver", "Mapa importado!", 4)
        else
            warn("[MapSaver] Erro ao importar:", err)
            setStatus("Erro ao importar: " .. tostring(err))
            notify("Erro ao importar", tostring(err), 6)
        end
    end)
end

----------------------------------------------------------------------
-- CONEXÕES
----------------------------------------------------------------------
for i = 1, 4 do
    cornerBtns[i].MouseButton1Click:Connect(function()
        setPosition(i)
    end)
end

ModeBtn.MouseButton1Click:Connect(function()
    state.useArea = not state.useArea
    refreshOptions()
    refreshAreaStatus()
end)

AnchorBtn.MouseButton1Click:Connect(function()
    state.anchor = not state.anchor
    refreshOptions()
end)

MeshBtn.MouseButton1Click:Connect(function()
    state.meshBlock = not state.meshBlock
    refreshOptions()
end)

BlockBtn.MouseButton1Click:Connect(function()
    state.block = not state.block
    refreshOptions()
end)

LangBtn.MouseButton1Click:Connect(function()
    state.lang = state.lang % #LANGS + 1
    NamesBox.Text = LANGS[state.lang][2]
    refreshOptions()
end)

SaveBtn.MouseButton1Click:Connect(salvarMapa)
ImportBtn.MouseButton1Click:Connect(importarMapa)

ClearBtn.MouseButton1Click:Connect(function()
    positions = { nil, nil, nil, nil }
    clearMarkers()

    for i = 1, 4 do
        cornerBtns[i].BackgroundColor3 = C.blue
        cornerBtns[i].Text = "Setar " .. i
    end

    refreshAreaStatus()
end)

-- Minimizar / fechar
local minimized = false
MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    Body.Visible = not minimized
    Status.Visible = not minimized
    Main.Size = minimized and UDim2.new(0, MAIN_W, 0, HEADER_H) or UDim2.new(0, MAIN_W, 0, MAIN_H)
    MinBtn.Text = minimized and "+" or "-"
end)

CloseBtn.MouseButton1Click:Connect(function()
    clearMarkers()
    ScreenGui:Destroy()
end)

-- Arrastar pelo cabeçalho (mouse e toque)
local dragging = false
local dragStart, startPos

Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

local dragConn = UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        Main.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

ScreenGui.Destroying:Connect(function()
    dragConn:Disconnect()
end)

refreshOptions()
print("[MapSaver v3] Menu carregado! Marque os 4 cantos > Salvar mapa")
