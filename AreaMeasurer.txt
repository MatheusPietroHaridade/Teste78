--[[
    Area Measurer
    Marca 4 posições e calcula o tamanho da área em studs
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Remove GUI antiga se existir
if PlayerGui:FindFirstChild("AreaMeasurerGui") then
    PlayerGui.AreaMeasurerGui:Destroy()
end

local positions = {
    [1] = nil,
    [2] = nil,
    [3] = nil,
    [4] = nil
}

local markers = {} -- para guardar as bolinhas visuais

----------------------------------------------------------------------
-- FUNÇÕES
----------------------------------------------------------------------
local function getPlayerPosition()
    local char = LocalPlayer.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
    if not root then return nil end
    return root.Position
end

local function createMarker(pos, number)
    -- Remove marcador antigo desse número
    if markers[number] then
        markers[number]:Destroy()
    end

    local part = Instance.new("Part")
    part.Name = "AreaMarker_" .. number
    part.Size = Vector3.new(2, 2, 2)
    part.Shape = Enum.PartType.Ball
    part.Anchored = true
    part.CanCollide = false
    part.Material = Enum.Material.Neon
    part.Color = Color3.fromRGB(0, 255, 100)
    part.Position = pos + Vector3.new(0, 3, 0)
    part.Parent = workspace

    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 60, 0, 40)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = part

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = tostring(number)
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0
    label.Font = Enum.Font.GothamBold
    label.TextSize = 24
    label.Parent = billboard

    markers[number] = part
end

local function clearMarkers()
    for i, marker in pairs(markers) do
        if marker then
            marker:Destroy()
        end
    end
    markers = {}
end

local function calculateArea()
    if not (positions[1] and positions[2] and positions[3] and positions[4]) then
        return nil
    end

    local p1, p2, p3, p4 = positions[1], positions[2], positions[3], positions[4]

    -- Distâncias entre os pontos (lados)
    local d12 = (p1 - p2).Magnitude
    local d23 = (p2 - p3).Magnitude
    local d34 = (p3 - p4).Magnitude
    local d41 = (p4 - p1).Magnitude

    -- Diagonais
    local d13 = (p1 - p3).Magnitude
    local d24 = (p2 - p4).Magnitude

    -- Bounding Box (caixa que envolve os 4 pontos)
    local minX = math.min(p1.X, p2.X, p3.X, p4.X)
    local maxX = math.max(p1.X, p2.X, p3.X, p4.X)
    local minZ = math.min(p1.Z, p2.Z, p3.Z, p4.Z)
    local maxZ = math.max(p1.Z, p2.Z, p3.Z, p4.Z)
    local minY = math.min(p1.Y, p2.Y, p3.Y, p4.Y)
    local maxY = math.max(p1.Y, p2.Y, p3.Y, p4.Y)

    local width  = maxX - minX   -- eixo X
    local length = maxZ - minZ   -- eixo Z
    local height = maxY - minY   -- eixo Y

    local areaXZ = width * length  -- área no chão (mais importante)

    return {
        d12 = d12,
        d23 = d23,
        d34 = d34,
        d41 = d41,
        d13 = d13,
        d24 = d24,
        width = width,
        length = length,
        height = height,
        area = areaXZ
    }
end

local function updateResultLabel(label)
    local result = calculateArea()
    if not result then
        label.Text = "Marque os 4 pontos para calcular"
        return
    end

    label.Text = string.format(
        "Lado 1→2: %.1f studs\n" ..
        "Lado 2→3: %.1f studs\n" ..
        "Lado 3→4: %.1f studs\n" ..
        "Lado 4→1: %.1f studs\n\n" ..
        "Largura (X): %.1f\n" ..
        "Comprimento (Z): %.1f\n" ..
        "Altura (Y): %.1f\n\n" ..
        "ÁREA TOTAL: %.0f studs²",
        result.d12, result.d23, result.d34, result.d41,
        result.width, result.length, result.height,
        result.area
    )
end

----------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AreaMeasurerGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 260, 0, 420)
Main.Position = UDim2.new(0.02, 0, 0.25, 0)
Main.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 12)
Corner.Parent = Main

-- Título
local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 40)
Title.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
Title.BorderSizePixel = 0
Title.Text = "Medidor de Área"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 18
Title.Parent = Main

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 12)
TitleCorner.Parent = Title

-- Botões Setar 1 a 4
local function createSetButton(number, yPos)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.85, 0, 0, 36)
    btn.Position = UDim2.new(0.075, 0, 0, yPos)
    btn.BackgroundColor3 = Color3.fromRGB(50, 120, 220)
    btn.Text = "Setar " .. number
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 15
    btn.Parent = Main

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 8)
    btnCorner.Parent = btn

    return btn
end

local btn1 = createSetButton(1, 55)
local btn2 = createSetButton(2, 100)
local btn3 = createSetButton(3, 145)
local btn4 = createSetButton(4, 190)

-- Label de resultado
local ResultLabel = Instance.new("TextLabel")
ResultLabel.Size = UDim2.new(0.9, 0, 0, 160)
ResultLabel.Position = UDim2.new(0.05, 0, 0, 245)
ResultLabel.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
ResultLabel.BorderSizePixel = 0
ResultLabel.Text = "Marque os 4 pontos para calcular"
ResultLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
ResultLabel.Font = Enum.Font.Gotham
ResultLabel.TextSize = 13
ResultLabel.TextXAlignment = Enum.TextXAlignment.Left
ResultLabel.TextYAlignment = Enum.TextYAlignment.Top
ResultLabel.TextWrapped = true
ResultLabel.Parent = Main

local ResultCorner = Instance.new("UICorner")
ResultCorner.CornerRadius = UDim.new(0, 8)
ResultCorner.Parent = ResultLabel

local ResultPadding = Instance.new("UIPadding")
ResultPadding.PaddingLeft = UDim.new(0, 10)
ResultPadding.PaddingTop = UDim.new(0, 8)
ResultPadding.Parent = ResultLabel

-- Botão Limpar
local ClearBtn = Instance.new("TextButton")
ClearBtn.Size = UDim2.new(0.85, 0, 0, 32)
ClearBtn.Position = UDim2.new(0.075, 0, 0, 375)
ClearBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
ClearBtn.Text = "Limpar Tudo"
ClearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ClearBtn.Font = Enum.Font.GothamBold
ClearBtn.TextSize = 14
ClearBtn.Parent = Main

local ClearCorner = Instance.new("UICorner")
ClearCorner.CornerRadius = UDim.new(0, 8)
ClearCorner.Parent = ClearBtn

----------------------------------------------------------------------
-- CONEXÕES
----------------------------------------------------------------------
local function setPosition(number)
    local pos = getPlayerPosition()
    if not pos then
        warn("[AreaMeasurer] Personagem não encontrado")
        return
    end

    positions[number] = pos
    createMarker(pos, number)

    -- Muda a cor do botão para indicar que foi setado
    local buttons = {btn1, btn2, btn3, btn4}
    buttons[number].BackgroundColor3 = Color3.fromRGB(40, 180, 80)
    buttons[number].Text = "Setar " .. number .. " ✓"

    updateResultLabel(ResultLabel)

    print(string.format("[AreaMeasurer] Posição %d setada: %.1f, %.1f, %.1f", number, pos.X, pos.Y, pos.Z))
end

btn1.MouseButton1Click:Connect(function() setPosition(1) end)
btn2.MouseButton1Click:Connect(function() setPosition(2) end)
btn3.MouseButton1Click:Connect(function() setPosition(3) end)
btn4.MouseButton1Click:Connect(function() setPosition(4) end)

ClearBtn.MouseButton1Click:Connect(function()
    positions = {[1]=nil, [2]=nil, [3]=nil, [4]=nil}
    clearMarkers()

    btn1.BackgroundColor3 = Color3.fromRGB(50, 120, 220)
    btn1.Text = "Setar 1"
    btn2.BackgroundColor3 = Color3.fromRGB(50, 120, 220)
    btn2.Text = "Setar 2"
    btn3.BackgroundColor3 = Color3.fromRGB(50, 120, 220)
    btn3.Text = "Setar 3"
    btn4.BackgroundColor3 = Color3.fromRGB(50, 120, 220)
    btn4.Text = "Setar 4"

    ResultLabel.Text = "Marque os 4 pontos para calcular"
    print("[AreaMeasurer] Tudo limpo")
end)

print("[AreaMeasurer] Menu carregado! Vá até cada canto e clique em Setar 1, 2, 3 e 4.")
