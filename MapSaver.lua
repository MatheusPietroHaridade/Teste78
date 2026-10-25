--[[
    Map Saver / Importer (versão melhorada)
    - Raio de 800 metros
    - Só cria Pastas e Models se tiverem conteúdo real dentro do raio
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

if PlayerGui:FindFirstChild("MapSaverGui") then
    PlayerGui.MapSaverGui:Destroy()
end

local FILE_NAME = "SavedMap.lua"
local MAX_DISTANCE = 800 -- metros (aumentado para cidade)

----------------------------------------------------------------------
-- FUNÇÕES AUXILIARES
----------------------------------------------------------------------
local function serializeCFrame(cf)
    local c = {cf:GetComponents()}
    return "CFrame.new(" .. table.concat(c, ", ") .. ")"
end

local function serializeColor3(c)
    return string.format("Color3.new(%.4f, %.4f, %.4f)", c.R, c.G, c.B)
end

local function getPosition(obj)
    if obj:IsA("BasePart") then
        return obj.Position
    elseif obj:IsA("Model") then
        if obj.PrimaryPart then
            return obj.PrimaryPart.Position
        end
        local success, cf = pcall(function()
            return obj:GetBoundingBox()
        end)
        if success then
            return cf.Position
        end
    end
    return nil
end

local function isWithinRange(obj, origin)
    local pos = getPosition(obj)
    if not pos then return false end
    return (pos - origin).Magnitude <= MAX_DISTANCE
end

-- Verifica se o objeto ou algum descendente está dentro do raio
local function hasContentInRange(obj, origin)
    if obj:IsA("BasePart") then
        return isWithinRange(obj, origin)
    end

    for _, descendant in ipairs(obj:GetDescendants()) do
        if descendant:IsA("BasePart") and isWithinRange(descendant, origin) then
            return true
        end
    end
    return false
end

----------------------------------------------------------------------
-- GERADOR DO CÓDIGO
----------------------------------------------------------------------
local function generateSaveCode()
    local character = LocalPlayer.Character
    local origin = Vector3.new(0, 0, 0)

    if character then
        local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
        if root then
            origin = root.Position
        end
    end

    local code = [[
-- Mapa salvo (apenas objetos a até 800m do jogador)
local objs = {}

local mapFolder = Instance.new("Folder")
mapFolder.Name = "ImportedMap"
mapFolder.Parent = workspace
objs[0] = mapFolder

]]

    local index = 0

    local function process(obj, parentIndex)
        local className = obj.ClassName

        -- Ignora MeshPart e classes que não queremos
        if className == "MeshPart" then return end
        if not (className == "Part" or className == "Model" or className == "Folder") then return end

        -- Filtro principal:
        -- Part → precisa estar no raio
        -- Model / Folder → só continua se tiver alguma Part dentro do raio
        if className == "Part" then
            if not isWithinRange(obj, origin) then
                return
            end
        else
            if not hasContentInRange(obj, origin) then
                return -- Pasta ou Model longe e sem conteúdo próximo → ignora completamente
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
            process(child, 0)
        end
    end

    code = code .. 'print("[MapSaver] Mapa importado com sucesso! Objetos criados: " .. ' .. index .. ')\n'
    return code
end

----------------------------------------------------------------------
-- SALVAR / IMPORTAR
----------------------------------------------------------------------
local function salvarMapa()
    local success, err = pcall(function()
        local code = generateSaveCode()

        if writefile then
            writefile(FILE_NAME, code)
            print("[MapSaver] Mapa salvo em:", FILE_NAME)
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "MapSaver",
                Text = "Mapa salvo (800m)!",
                Duration = 4
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
Main.Size = UDim2.new(0, 220, 0, 140)
Main.Position = UDim2.new(0.5, -110, 0.3, 0)
Main.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 10)
Corner.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 36)
Title.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
Title.BorderSizePixel = 0
Title.Text = "Map Saver"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 16
Title.Parent = Main

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = Title

local SaveBtn = Instance.new("TextButton")
SaveBtn.Size = UDim2.new(0.85, 0, 0, 36)
SaveBtn.Position = UDim2.new(0.075, 0, 0, 50)
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
ImportBtn.Position = UDim2.new(0.075, 0, 0, 95)
ImportBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
ImportBtn.Text = "ImportarMapa"
ImportBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ImportBtn.Font = Enum.Font.GothamBold
ImportBtn.TextSize = 15
ImportBtn.Parent = Main

local ImportCorner = Instance.new("UICorner")
ImportCorner.CornerRadius = UDim.new(0, 8)
ImportCorner.Parent = ImportBtn

SaveBtn.MouseButton1Click:Connect(salvarMapa)
ImportBtn.MouseButton1Click:Connect(importarMapa)

print("[MapSaver] Menu carregado! Raio: 800m + filtro inteligente de pastas")
