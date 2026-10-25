--[[
    Map Saver com Área Marcada
    1. Setar 1, 2, 3 e 4 para demarcar a área
    2. Clicar em SalvarMapa
    3. Só salva o que estiver DENTRO da área marcada
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

if PlayerGui:FindFirstChild("MapSaverGui") then
    PlayerGui.MapSaverGui:Destroy()
end

local FILE_NAME = "SavedMap.lua"

local positions = {
    [1] = nil,
    [2] = nil,
    [3] = nil,
    [4] = nil
}

local markers = {}

----------------------------------------------------------------------
-- FUNÇÕES DE ÁREA
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
    local minY = math.min(p1.Y, p2.Y, p3.Y, p4.Y) - 50
    local maxY = math.max(p1.Y, p2.Y, p3.Y, p4.Y) + 150

    return {
        minX = minX, maxX = maxX,
        minZ = minZ, maxZ = maxZ,
        minY = minY, maxY = maxY,
        width = maxX - minX,
        length = maxZ - minZ
    }
end

local function isInsideArea(pos, bounds)
    if not bounds then return false end
    return pos.X >= bounds.minX and pos.X <= bounds.maxX
       and pos.Z >= bounds.minZ and pos.Z <= bounds.maxZ
       and pos.Y >= bounds.minY and pos.Y <= bounds.maxY
end

local function hasContentInArea(obj, bounds)
    if obj:IsA("BasePart") then
        return isInsideArea(obj.Position, bounds)
    end

    for _, descendant in ipairs(obj:GetDescendants()) do
        if descendant:IsA("BasePart") and isInsideArea(descendant.Position, bounds) then
            return true
        end
    end
    return false
end

----------------------------------------------------------------------
-- SERIALIZER
----------------------------------------------------------------------
local function serializeCFrame(cf)
    local c = {cf:GetComponents()}
    return "CFrame.new(" .. table.concat(c, ", ") .. ")"
end

local function serializeColor3(c)
    return string.format("Color3.new(%.4f, %.4f, %.4f)", c.R, c.G, c.B)
end

local function generateSaveCode(bounds)
    local code = [[
-- Mapa salvo pela área marcada
local objs = {}

local mapFolder = Instance.new("Folder")
mapFolder.Name = "ImportedMap"
mapFolder.Parent = workspace
objs[0] = mapFolder

]]

    local index = 0

    local function process(obj, parentIndex)
        local className = obj.ClassName

        if className == "MeshPart" then return end
        if not (className == "Part" or className == "Model" or className == "Folder") then return end

        if className == "Part" then
            if not isInsideArea(obj.Position, bounds) then
                return
            end
        else
            if not hasContentInArea(obj, bounds) then
                return
            end
        end

        index = index + 1
        local currentIndex = index

        if className == "Part" then
            code = code .. string.format("objs[%d] = Instance.new(\"Part\")\n", currentIndex)
            code = code .. string.format("objs[%d].Name = %q\n", currentIndex, obj.Name)
            code = code .. string.format("objs[%d].Size = Vector3.new(%.4f, %.4f, %.4f)\n", currentIndex, obj.Size.X, obj.Size.Y, obj.Size.Z)
            code = code .. string.format("objs[%d].CFrame = %s\n", currentIndex, serializeCFrame(obj.CFrame))
            code = code .. string.format("objs[%d].Color = %s\n", currentIndex, serializeColor3(obj.Color))
            code = code .. string.format("objs[%d].Material = Enum.Material.%s\n", currentIndex, obj.Material.Name)
            code = code .. string.format("objs[%d].Transparency = %s\n", currentIndex, obj.Transparency)
            code = code .. string.format("objs[%d].Reflectance = %s\n", currentIndex, obj.Reflectance)
            code = code .. string.format("objs[%d].CanCollide = %s\n", currentIndex, tostring(obj.CanCollide))
            code = code .. string.format("objs[%d].Anchored = true\n", currentIndex)
            if obj.Shape ~= Enum.PartType.Block then
                code = code .. string.format("objs[%d].Shape = Enum.PartType.%s\n", currentIndex, obj.Shape.Name)
            end
            code = code .. string.format("objs[%d].Parent = objs[%d]\n\n", currentIndex, parentIndex)

        elseif className == "Model" or className == "Folder" then
            code = code .. string.format("objs[%d] = Instance.new(%q)\n", currentIndex, className)
            code = code .. string.format("objs[%d].Name = %q\n", currentIndex, obj.Name)
            code = code .. string.format("objs[%d].Parent = objs[%d]\n\n", currentIndex, parentIndex)

            for _, child in ipairs(obj:GetChildren()) do
                process(child, currentIndex)
            end
        end
    end

    for _, child in ipairs(workspace:GetChildren()) do
        if child.Name ~= "Camera" and not child:IsA("Terrain") and not Players:GetPlayerFromCharacter(child) then
            if not child.Name:match("^AreaMarker_") then
                process(child, 0)
            end
        end
    end

    code = code .. 'print("[MapSaver] Mapa importado com sucesso! Objetos criados: " .. ' .. index .. ')\n'
    return code, index
end

----------------------------------------------------------------------
-- SALVAR / IMPORTAR
----------------------------------------------------------------------
local function salvarMapa()
    local bounds = getAreaBounds()
    if not bounds then
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "MapSaver",
            Text = "Marque os 4 pontos primeiro!",
            Duration = 4
        })
        return
    end

    local success, err = pcall(function()
        local code, count = generateSaveCode(bounds)

        if writefile then
            writefile(FILE_NAME, code)
            print("[MapSaver] Mapa salvo! Objetos:", count)
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "MapSaver",
                Text = "Salvo! (" .. count .. " objetos)",
                Duration = 5
            })
        elseif setclipboard then
            setclipboard(code)
            print("[MapSaver] Código copiado para clipboard")
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "MapSaver",
                Text = "Copiado para clipboard!",
                Duration = 4
            })
        else
            error("Executor sem writefile e sem setclipboard")
        end
    end)

    if not success then
        warn("[MapSaver] Erro ao salvar:", err)
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Erro ao salvar",
            Text = tostring(err),
            Duration = 6
        })
    end
end

local function importarMapa()
    local success, err = pcall(function()
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

        local func, loadErr = loadstring(code)
        if not func then
            error("Erro ao carregar código: " .. tostring(loadErr))
        end

        func()
    end)

    if not success then
        warn("[MapSaver] Erro ao importar:", err)
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Erro ao importar",
            Text = tostring(err),
            Duration = 6
        })
    end
end

----------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MapSaverGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 240, 0, 390)
Main.Position = UDim2.new(0.02, 0, 0.2, 0)
Main.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 12)
Corner.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 38)
Title.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
Title.BorderSizePixel = 0
Title.Text = "Map Saver + Área"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 16
Title.Parent = Main

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 12)
TitleCorner.Parent = Title

local function createSetButton(number, yPos)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.85, 0, 0, 32)
    btn.Position = UDim2.new(0.075, 0, 0, yPos)
    btn.BackgroundColor3 = Color3.fromRGB(50, 120, 220)
    btn.Text = "Setar " .. number
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 14
    btn.Parent = Main

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 7)
    btnCorner.Parent = btn

    return btn
end

local btn1 = createSetButton(1, 50)
local btn2 = createSetButton(2, 88)
local btn3 = createSetButton(3, 126)
local btn4 = createSetButton(4, 164)

local InfoLabel = Instance.new("TextLabel")
InfoLabel.Size = UDim2.new(0.9, 0, 0, 40)
InfoLabel.Position = UDim2.new(0.05, 0, 0, 205)
InfoLabel.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
InfoLabel.BorderSizePixel = 0
InfoLabel.Text = "Marque os 4 cantos da área"
InfoLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
InfoLabel.Font = Enum.Font.Gotham
InfoLabel.TextSize = 12
InfoLabel.TextWrapped = true
InfoLabel.Parent = Main

local InfoCorner = Instance.new("UICorner")
InfoCorner.CornerRadius = UDim.new(0, 7)
InfoCorner.Parent = InfoLabel

local SaveBtn = Instance.new("TextButton")
SaveBtn.Size = UDim2.new(0.85, 0, 0, 36)
SaveBtn.Position = UDim2.new(0.075, 0, 0, 255)
SaveBtn.BackgroundColor3 = Color3.fromRGB(40, 180, 80)
SaveBtn.Text = "SalvarMapa"
SaveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SaveBtn.Font = Enum.Font.GothamBold
SaveBtn.TextSize = 15
SaveBtn.Parent = Main

local SaveCorner = Instance.new("UICorner")
SaveCorner.CornerRadius = UDim.new(0, 8)
SaveCorner.Parent = SaveBtn

local ImportBtn = Instance.new("TextButton")
ImportBtn.Size = UDim2.new(0.85, 0, 0, 36)
ImportBtn.Position = UDim2.new(0.075, 0, 0, 300)
ImportBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
ImportBtn.Text = "ImportarMapa"
ImportBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ImportBtn.Font = Enum.Font.GothamBold
ImportBtn.TextSize = 15
ImportBtn.Parent = Main

local ImportCorner = Instance.new("UICorner")
ImportCorner.CornerRadius = UDim.new(0, 8)
ImportCorner.Parent = ImportBtn

local ClearBtn = Instance.new("TextButton")
ClearBtn.Size = UDim2.new(0.85, 0, 0, 30)
ClearBtn.Position = UDim2.new(0.075, 0, 0, 345)
ClearBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
ClearBtn.Text = "Limpar Marcadores"
ClearBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
ClearBtn.Font = Enum.Font.GothamBold
ClearBtn.TextSize = 13
ClearBtn.Parent = Main

local ClearCorner = Instance.new("UICorner")
ClearCorner.CornerRadius = UDim.new(0, 7)
ClearCorner.Parent = ClearBtn

----------------------------------------------------------------------
-- CONEXÕES
----------------------------------------------------------------------
local function setPosition(number)
    local pos = getPlayerPosition()
    if not pos then
        warn("[MapSaver] Personagem não encontrado")
        return
    end

    positions[number] = pos
    createMarker(pos, number)

    local buttons = {btn1, btn2, btn3, btn4}
    buttons[number].BackgroundColor3 = Color3.fromRGB(40, 180, 80)
    buttons[number].Text = "Setar " .. number .. " ✓"

    local bounds = getAreaBounds()
    if bounds then
        InfoLabel.Text = string.format("Área: %.0f x %.0f studs", bounds.width, bounds.length)
    else
        local count = 0
        for i = 1, 4 do
            if positions[i] then count = count + 1 end
        end
        InfoLabel.Text = "Pontos marcados: " .. count .. "/4"
    end

    print(string.format("[MapSaver] Posição %d setada", number))
end

btn1.MouseButton1Click:Connect(function() setPosition(1) end)
btn2.MouseButton1Click:Connect(function() setPosition(2) end)
btn3.MouseButton1Click:Connect(function() setPosition(3) end)
btn4.MouseButton1Click:Connect(function() setPosition(4) end)

SaveBtn.MouseButton1Click:Connect(salvarMapa)
ImportBtn.MouseButton1Click:Connect(importarMapa)

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

    InfoLabel.Text = "Marque os 4 cantos da área"
    print("[MapSaver] Marcadores limpos")
end)

print("[MapSaver] Menu carregado! Marque os 4 cantos → SalvarMapa")
