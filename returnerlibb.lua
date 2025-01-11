local bot = {}

-- services
local players            = game:GetService("Players")
local httpService        = game:GetService("HttpService")
local starterGui         = game:GetService("StarterGui")
local replicatedStorage  = game:GetService("ReplicatedStorage")
local teleportService    = game:GetService("TeleportService")
local pathfindingService = game:GetService("PathfindingService")

local localPlayer        = players.LocalPlayer or players.PlayerAdded:Wait()
local character          = localPlayer.Character or localPlayer.CharacterAdded:Wait()
local humanoidRootPart   = character:WaitForChild("HumanoidRootPart")
local humanoid           = character:WaitForChild("Humanoid")

-- make sure getgenv().Settings exists
getgenv().Settings = getgenv().Settings or {}

-- single lines table
bot.lines = getgenv().Settings.lines or {
    "[ReturnerBOT] ERROR! Lines table is invalid, please fix this in your script."
}

-- each teleport location is a table with {name = "...", cframe = CFrame}
-- you can rename them freely
bot.teleportLocations = getgenv().Settings.teleportLocations or {
    { name = "Start", cframe = CFrame.new(0, 0, 0) }
}

-- fallback toggles
getgenv().disableAnimate   = getgenv().disableAnimate   or false
getgenv().animationPack    = getgenv().animationPack    or nil
getgenv().randomAnimations = getgenv().randomAnimations or false
getgenv().smallMode        = getgenv().smallMode        or false
getgenv().walkSpeed        = getgenv().walkSpeed        or 16
getgenv().Speed            = getgenv().Speed            or 5
getgenv().noClip           = getgenv().noClip           or false
getgenv().chatMode         = getgenv().chatMode         or "old"
getgenv().scriptUrl        = getgenv().scriptUrl        or nil

-- example storing staff/team data
bot.cuffRanks      = {7,9,10,11,12,14,15,16}
bot.roomRanks      = {8,9,10,11,12,14,15,16}
bot.teleportPlace  = 4483381587
bot.teams          = {"LRs","MRs","HRs"}
bot.staff          = {}
bot.botGoing       = "starting"

-- decode/encode
function bot.decode(str)
    return httpService:JSONDecode(str)
end

function bot.encode(tbl)
    return httpService:JSONEncode(tbl)
end

-- notify
function bot.notify(title, text, duration)
    pcall(function()
        starterGui:SetCore("SendNotification", {
            Title    = title,
            Text     = text,
            Duration = duration or 5
        })
    end)
end

-- safe wait for game
function bot.waitGame()
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end
end

-- pathfinding walk
function bot.walkTo(posVector)
    print("Walking to position:", posVector)
    local agentParams = {
        AgentCanJump = true,
        Costs = { seat = math.huge }
    }
    local path = pathfindingService:CreatePath(agentParams)
    local startPos = humanoidRootPart.Position - Vector3.new(0, humanoidRootPart.Size.Y / 0.75, 0)
    path:ComputeAsync(startPos, posVector)
    
    print("Path Status:", path.Status)
    if path.Status ~= Enum.PathStatus.Success then
        warn("Pathfinding failed with status:", path.Status)
        return
    end
    
    local waypoints = path:GetWaypoints()
    print("Number of waypoints:", #waypoints)
    
    for index, waypoint in ipairs(waypoints) do
        print("Waypoint "..index..": Position:", waypoint.Position, "Action:", waypoint.Action)
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoid.Jump = true
            print("Humanoid jumping at waypoint "..index)
        end
        humanoid:MoveTo(waypoint.Position)
        local success, errorMessage = pcall(function()
            humanoid.MoveToFinished:Wait()
        end)
        if not success then
            warn("Error during MoveToFinished: ", errorMessage)
        else
            print("Reached waypoint "..index)
        end
    end
    print("Reached position:", posVector)
end


-- finds a cframe by the user-defined name (returns nil if not found)
function bot.findLocation(name)
    for _, loc in ipairs(bot.teleportLocations) do
        if loc.name == name then
            return loc.cframe
        end
    end
    return nil
end

-- getRandomItem function
function bot.getRandomItem(listOfLines, lastLine)
    -- if there's nothing in the list, just return empty string or nil
    if #listOfLines == 0 then
        return ""
    end

    -- random seed (optional; done once at init is often enough)
    math.randomseed(os.time())

    local length = #listOfLines
    local index  = math.random(1, length)

    -- if there is more than one line and we keep hitting the same line, roll again
    if length > 1 then
        while listOfLines[index] == lastLine do
            index = math.random(1, length)
        end
    end

    return listOfLines[index]
end

-- goTo by name, won't break if user renamed a location
function bot.goTo(locationName)
    print("Attempting to go to:", locationName)
    local cframe = bot.findLocation(locationName)
    if not cframe then
        warn("bot.goTo: location '"..locationName.."' not found in settings; skipping")
        return
    end
    bot.walkTo(cframe.Position)
    print("Successfully navigated to:", locationName)
end

-- go to start
function bot.toStart()
    local fallbackStart = CFrame.new(6, 201, -274)
    -- look for "starting" in user table
    local cframe = bot.findLocation("starting") or fallbackStart
    humanoidRootPart.CFrame = cframe
    print("Moved to start position.")
end




-- say line from a single big table
bot.lastChatItem = nil
function bot.sayLine(linesTable)
    local line = bot.getRandomItem(linesTable, bot.lastChatItem)
    bot.say(line)  -- Corrected: Only pass one argument
    bot.lastChatItem = line
end

function bot.say(msg)
    if getgenv().chatMode == "old" then
        replicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(msg, "All")
    else
        game:GetService("TextChatService").TextChannels.RBXGeneral:SendAsync(msg)
    end
    print("Said message:", msg)
end

-- simple rejoin logic
function bot.queueTeleport()
    -- Ensure scriptUrl is defined
    if not getgenv().scriptUrl then
        warn("bot.queueTeleport: 'scriptUrl' is not defined in getgenv().Settings")
        return
    end
    
    -- Serialize the scriptUrl to safely include it in the queued teleport script
    local encodedScriptUrl = tostring(getgenv().scriptUrl):gsub('"', '\\"') -- Escape any double quotes
    
    queue_on_teleport([[
        if not game:IsLoaded() then
            game.Loaded:Wait()
        end
        
        -- Optionally, add error handling for the HTTP request
        local success, response = pcall(function()
            return game:HttpGet("]] .. encodedScriptUrl .. [[")
        end)
        
        if success then
            local func, loadError = loadstring(response)
            if func then
                pcall(func)
            else
                warn("bot.queueTeleport: Failed to load script:", loadError)
            end
        else
            warn("bot.queueTeleport: Failed to fetch script:", response)
        end
    ]])
    print("Queued teleport with scriptUrl:", getgenv().scriptUrl)
end

bot.rejoinFlag = false
function bot.checkKicked()
    task.spawn(function()
        while true do
            for _, guiObj in pairs(game.CoreGui:GetDescendants()) do
                if guiObj:IsA("TextLabel") and guiObj.Name == "ErrorMessage" then
                    if guiObj.Text:match("You were kicked from this experience") then
                        print("Detected kick from experience.")
                        bot.queueTeleport()
                        task.wait(2)
                        bot.rejoinFlag = true
                        return
                    end
                end
            end
            task.wait(1)
        end
    end)
end

function bot.checkRejoin()
    spawn(function()
        game:GetService("RunService").RenderStepped:Connect(function()
            if bot.rejoinFlag then
                print("Rejoining the game...")
                teleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, localPlayer)
            end
        end)
    end)
end

-- small example of a route
function bot.exampleRoute()
    -- these are example location names
    -- if the user renames them in their script, we'll skip them if not found
    local route = {"starting","carpet","leftFish","rightFish","carpet"}
    for _, locName in ipairs(route) do
        bot.goTo(locName)
        bot.sayLine(bot.lines)
        task.wait(2)
    end
    bot.notify("Route", "Example route complete.", 5)
    print("Executed example route.")
end

-- no clip
function bot.noClipAll()
    if getgenv().noClip then
        print("Activating noClip.")
        local floorPart = Instance.new("Part")
        floorPart.Name         = "CCFloor"
        floorPart.Size         = Vector3.new(1000,1,1000)
        floorPart.Position     = Vector3.new(0,40.6,0)
        floorPart.CanCollide   = true
        floorPart.Transparency = 1
        floorPart.Parent       = workspace
        floorPart.Anchored     = true

        for _,obj in pairs(workspace:GetDescendants()) do
            if obj.Name ~= "CCFloor" and obj.Name ~= "StaffArea" and obj.Name ~= "ReturnerBOT" then
                if obj:IsA("BasePart") then
                    obj.CanCollide = false
                end
            end
        end
        print("NoClip activated.")
    end
end

function bot.sitMonitor()
    task.spawn(function()
        while task.wait() do
            if humanoid.Sit then
                humanoid.Jump = true
                print("Detected sitting. Forced jump.")
            end
        end
    end)
end

-- small mode
function bot.smallMode()
    if getgenv().smallMode then
        print("Activating smallMode.")
        replicatedStorage:WaitForChild("DataEvents"):WaitForChild("sendMorphData"):FireServer("Toddler")
    end
end

-- simple animations
bot.animationIds = {
    ["Astronaut"] = {
        idle1 = "rbxassetid://891621366",
        idle2 = "rbxassetid://891633237",
        walk  = "rbxassetid://891667138",
        run   = "rbxassetid://891636393",
        jump  = "rbxassetid://891627522",
        fall  = "rbxassetid://891617961",
        climb = "rbxassetid://891609353"
    },
}
function bot.randomId(allIDs)
    local index = math.random(1, #allIDs)
    return allIDs[index]
end

function bot.setupAnimations()
    if getgenv().disableAnimate then
        local animScript = character:FindFirstChild("Animate")
        if animScript then
            animScript.Disabled = true
            print("Disabled Animate script.")
        end
        return
    end
    local animate = character:FindFirstChild("Animate")
    if not animate then
        print("Animate script not found.")
        return
    end

    if getgenv().randomAnimations then
        print("Applying random animations.")
        local allIDs = {}
        for _, packTbl in pairs(bot.animationIds) do
            for _, animId in pairs(packTbl) do
                table.insert(allIDs, animId)
            end
        end
        for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
            track:Stop()
        end
        animate.idle.Animation1.AnimationId = bot.randomId(allIDs)
        animate.idle.Animation2.AnimationId = bot.randomId(allIDs)
        animate.walk.WalkAnim.AnimationId   = bot.randomId(allIDs)
        animate.run.RunAnim.AnimationId     = bot.randomId(allIDs)
        animate.jump.JumpAnim.AnimationId   = bot.randomId(allIDs)
        animate.fall.FallAnim.AnimationId   = bot.randomId(allIDs)
        animate.climb.ClimbAnim.AnimationId = bot.randomId(allIDs)
        print("Random animations applied.")
    else
        local chosen = getgenv().animationPack
        if chosen and bot.animationIds[chosen] then
            print("Applying animation pack:", chosen)
            local anims = bot.animationIds[chosen]
            for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
                track:Stop()
            end
            animate.idle.Animation1.AnimationId = anims.idle1
            animate.idle.Animation2.AnimationId = anims.idle2
            animate.walk.WalkAnim.AnimationId   = anims.walk
            animate.run.RunAnim.AnimationId     = anims.run
            animate.jump.JumpAnim.AnimationId   = anims.jump
            animate.fall.FallAnim.AnimationId   = anims.fall
            animate.climb.ClimbAnim.AnimationId = anims.climb
            print("Animation pack applied:", chosen)
        else
            print("No valid animation pack chosen or pack does not exist.")
        end
    end
end

function bot.init()
    print("Bot initialization started.")
    math.randomseed(os.time()) -- Seed the RNG
    bot.waitGame()
    bot.toStart()
    bot.sitMonitor()
    bot.noClipAll()
    bot.setupAnimations()
    if humanoid then
        humanoid.WalkSpeed = getgenv().walkSpeed
        print("WalkSpeed set to:", getgenv().walkSpeed)
    end
    bot.smallMode()
    bot.checkKicked()
    bot.checkRejoin()

    bot.notify("ReturnerBOT", "Initialized successfully.", 5)
    print("Bot initialization completed.")
end

-- run
function bot.run()
    -- if you want an infinite loop or route cycle, do it here
    -- for demonstration, we won't start anything by default
    print("Bot run function called.")
end

function bot.test()
    print("test")
end

return bot
