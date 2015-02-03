
--require("mobdebug").start() -- Uncomment for ZeroBrain IDE debugger support
dofile("VirtualResolution.lua")
dofile("NodeUtility.lua")

-- This is our virtual screen size we will work with for all code
-- Try setting the simulator to something like 500 wide x 400 high and
-- restarting to see effect clearly.
-- Change surface width and height at runtime to see effect of orientation event
appWidth = 480
appHeight = 640

local vr = virtualResolution

vr:initialise{userSpaceW=appWidth, userSpaceH=appHeight}

-------------------------------------------------------------------------------

--helper functions for rotation

-- (0,0) are the world coords of the bottom left of our user coord area.
-- Here we get the screen size in user coords, plus screen min and max coords
-- in user space. We can use these to draw outside the screen area while still
-- using VR for the scene. See bottom of code...

function updateVrGlobals()
    -- User space values of screen edges: for detecting edges of full screen area, including letterbox/borders
    -- Useful for making sure things are on/off screen when needed
    screenWidth = vr:winToUserSize(director.displayWidth)
    screenHeight = vr:winToUserSize(director.displayHeight)
    
    screenMinX = appWidth/2 - screenWidth/2
    screenMaxX = appWidth/2 + screenWidth/2
    screenMinY = appHeight/2 - screenHeight/2
    screenMaxY = appHeight/2 + screenHeight/2
end

-- call this whenever rotation happens to rescale everything
function updateVirtualResolution()
    -- check screne size and get new scaling values
    virtualResolution:update()
    
    -- rescale the scene
    virtualResolution:applyToScene(director:getCurrentScene())
    
    -- update our apps screen globals
    updateVrGlobals()
end


-------------------------------------------------------------------------------

--Now we actually "turn on" VR

local scene = director:getCurrentScene()
vr:applyToScene(scene)
updateVrGlobals()
system:addEventListener("orientation", updateVirtualResolution)

--NB: must call applyToScene before creating any nodes in that scene!

--Usually, you prob want to do the above in relevant scene events, e.g.
--   myScene:setUp()
--       vr:applyToScene(self)
--   end
--   
--   myScene:orientation()
--       updateVrGlobals(self)
--   end
--
--   function updateVirtualResolution(scene)
--       --etc, note we can have a global helper and pass it the scene
--   end


-------------------------------------------------------------------------------

-- Some simple physics simulation so we have something to look at...

-- Touch to add ball that falls under gravity
function touchListener(event)
    local x,y = vr:getUserPos(event.x, event.y)
    
    if event.phase == "began" then
        local ball = director:createSprite({x=x, y=y, source="textures/beachball.png", xAnchor=0.5, yAnchor=0.5})
        setDefaultSize(ball, 40)
        physics:addNode(ball, {radius=20})
    end
end

system:addEventListener("touch", touchListener)

-- Use accelerometer to change gravity for fun!

-- on startup, all gravity is in Y!
gravityX, gravity = physics:getGravity()

function accelListener(event)
    --if accel not supported, these are always zero
    if event.x == 0 and event.y == 0 then
        return
    end
    
    physics:setGravity(-event.x*gravity, -event.y*gravity)
end

system:addEventListener("accelerometer", accelListener)

-- Background
local sky = director:createSprite(0, 0, "textures/epic-sky.jpg")
setDefaultSize(sky, appWidth, appHeight)

-- Add floor and walls to bounce off
local ground = director:createSprite(-(appHeight-appWidth)/2, -15, "textures/WalkwayLong.png")
physics:addNode(ground, {type="static"})
setDefaultSize(ground, appHeight)

local leftWall = director:createSprite(-15, appHeight, "textures/WalkwayLong.png")
leftWall.rotation = 90
setDefaultSize(leftWall, appHeight)
physics:addNode(leftWall, {type="static"})

local rightWall = director:createSprite(appWidth+15, 0, "textures/WalkwayLong.png")
rightWall.rotation = 270
setDefaultSize(rightWall, appHeight)
physics:addNode(rightWall, {type="static"})

-- Show how we could do some drawing in the borders
-- This is in screen space, not VR/user space
director:createRectangle({x=screenMinX+20, y=screenMinY+20, w=screenWidth-40, h=screenHeight-40,
        alpha=0, strokeWidth=10, zOrder = -1})
