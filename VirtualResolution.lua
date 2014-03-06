
 --[[
    (C) Nick Smith 2014
    Flexible virtual resolution system for use with Marmalade Quick
    
    Implements a virtual resolution scaling system, with letterboxes that can
    be drawn over. A singleton table scales a scene between user coord space &
    screen/window space
  
    Overview:
    Set the size of the coordinate space you want to use for the scene, set the
    scene and then it will silently scale everything up to screen size.
    Can optionally scale touch events, but this has a performance hit and is
    pretty hacky! Note that Quick always returns *world* coord touch events.
  
    It is recommended to scale touches using either:
        virtualResolution:getUserX(x) -> screen to user "world" coords
    or
        getLocalCoords(worldX, worldY, localNode) -> screen to "local" coords
            Here, the returned values are relative to localNode.
            More powerful as it can go any depth down a child tree.
            From https://github.com/nickchops/MarmaladeQuickNodeUtility
            - not part of VirtualResolution.
  
    How it works:
    It adds a node called "scalerRootNode" to the scene, applies transforms to
    that and then overrides the scene node to add children to scalerRootNode
    instead of itself.
  
    Be careful if you use myScene.children. For example, if you loop through
    myScene.children to destroy all visual nodes, you will also destroy the
    scalerRootNode and cause havock :) It's recommeneded to always have an
    "origin" node in a scene, or use scene.children and explicitly ignore
    scene.scalerRootNode.
]]--

virtualResolution = {}


--[[ To use:

--Basics

virtualResolution:initialiseForUserCoordSpace(userSpaceW, userSpaceH)
-- Call this first, with width and height of "user space", aka "virtual resolution"
-- This will also get the window sizes and work out scaling and offset to apply

-- Then create scenes with director:createScene(...

virtualResolution:applyToScene(myScene)
-- Then call this for each scene you want to use virtual resolution on

virtualResolution:scaleTouchEvents(true)
-- Optionally set this true to make event.x and event.y values be returned in
-- user space rather than window/screen space. Not recommened as it reduces
-- performance of general event handling and is rather hacky. But good for
-- some quick testing.

virtualResolution:getUserX(event.x)
virtualResolution:getUserY(event.y)
-- If not using scaleTouchEvents(true), use these in event listeners to
-- translate world event positions to user space ones. Useful for touch!

-- For getters, its recommended to use shortcuts like:
vr = virtualResolution
vr.x = vr.getUserX
vr.y = vr.getUserY
--   then you can do
function myTouchListener(event)
    userX = vr.x(event.x)
    ...
end


--Advanced

virtualResolution:getWinX(userX)
virtualResolution:getWinX(userY)
-- Use these to translate user space to world space. Useful if you have NOT
-- called virtualResolution:applyToScene(myScene) and want to scale everything
-- manaully.

virtualResolution:updateWindowSize()
-- Call this is the window size changes (eg on desktop) to re-configure

virtualResolution:initialiseForUserCoordSpace(...)
-- Call this again if you want to change virtual resolution!

myScene.scalerRootNode
-- This node is added to a scene by virtualResolution:applyToScene() and does
-- the scaling. You can play with it manually if you want :)

virtualResolution:releaseScene(myScene, [false])
-- Call this when you are done with a scene. It will remove the scalerRootNode
-- that is silently doing the transforms. By default, any children of the scene
-- will be "kept" as they get moved from being children of the scaling node to
-- the scene itself. Pass false as the second param to stop this and remove any
-- children from the scene! If just destroying the scene, you probably dont
-- need this at all. There's No need to call this on transitioning from a scene

myScene:addChildNoTrans(node)
-- Calling virtualResolution:applyToScene() will cause the scenes :addChild()
-- calls to be redirected to myScene.scalerRootNode:addChild(). The original
-- method is "backed-up" via .addChildNoTrans. So, you can use
-- myScene:addChildNoTrans(node) to bypass virtual resolution and add nodes
-- that are "in window space".

]]--

--TODO add built in options for letterbox/borders

-----------------------------------------

-- Setup functions

function virtualResolution:updateWindowSize()
    self.winW = director.displayWidth
    self.winH = director.displayHeight
    self:update()
end

function virtualResolution:initialiseForUserCoordSpace(userSpaceW, userSpaceH)
    self.userW = userSpaceW
    self.userH = userSpaceH
    self:update()
end
    
function virtualResolution:update()
    if not self.winW then
        self:updateWindowSize()
    end
    
    if not self.userW then
        self.userW = self.winW
        self.userH = self.winH
    end
    
    self.winAspect = self.winW / self.winH
    self.userAspect = self.userW / self.userH
    
    if self.winAspect < self.userAspect then
        self.scale = self.winW / self.userW
        self.yOffset = (self.winH - self.userH*self.scale) / 2
        self.xOffset = 0
    else
        self.scale = self.winH / self.userH
        self.yOffset = 0
        self.xOffset = (self.winW - self.userW*self.scale) / 2
    end
    
    self.setup = true
end

-- Set a scene to be scaled and offset. Quality will depend on how well GL
-- scales everything
function virtualResolution:applyToScene(scene, transformActualScene)
    -- Sadly Quick does not handle transitions well with scaling of the scene object itself.
    -- What happens is the scene jumps between it's untransformed and scaled/positioned
    -- state during transitions, which looks poor. Adding scene:sync() doesnt fix,
    -- so likely an issue in the C++ engine/cocos2d (or side effect of optimisation).
    -- Marmalade ticket MAINT-2657 was opened to look into this.
    
    if not self.setup then
        dbg.assert("virtualResolution:applyToScene called before initialiseForUserCoordSpace")
        return
    end
    
    if scene.scalerRootNode then
        dbg.assert("virtualResolution:applyToScene called for scene already using virtual resolution")
        return
    end
    
    self.scaleTouch = false
    
    -- transforActualScene makes scaling just be applied to scene. May work if you
    -- dont use transiations. May still have other issues, not well tested.
    if transformActualScene then
        self.transViaScene = true
        scene.xScale = self.scale
        scene.yScale = self.scale
        scene.x = self.xOffset
        scene.y = self.yOffset
        return
    end
    
    -- To support transitions and get more control generally, we have to create
    -- a node, scale and move that, and override how the scene adds children
   
    scene.scalerRootNode = director:createNode({x=self.xOffset, y=self.yOffset, xScale=self.scale, yScale = self.scale})
    if not director.addNodesToScene or scene ~= director:getCurrentScene() then
        scene:addChild(scalerRootNode)
    end
    
    -- Override scene:addChild() to call scene.scalerRootNode:addChild()
    -- Note that we cant just do scene.addChild = scene.scalerRootNode.addChild
    -- because those .addChild functions are the same actual function value! It's the
    -- "self" value passed implicitly via : mechanism that determins which node is used!
    scene.addChildNoTrans = scene.addChild -- keep a backup so user can still add "window space" nodes
    scene.addChild = virtualResolutionSceneAddChildOverride
    
    -- note that scene:AddChild() is called internally via director:addNodeToLists()
    -- on director:createXXX() calls if director.addNodesToScene is true
end

function virtualResolutionSceneAddChildOverride(self, n)
    self.scalerRootNode:addChild(n)
end

-- note that you likley only ever want to call this if destroying a scene or
-- turning off virtual resolution (rare!). For the later, you will want to
-- first "move" all scene nodes from being children of the scaler node to
-- children of the scene itself. TODO: implement keepChildren to do that!
function virtualResolution:releaseScene(scene, keepChildren)
    scene.addChild = scene.addChildNoTrans
    scene.scalerRootNode:removeFromParent()
    scene.scalerRootNode = nil
end

-----------------------------------------------------------------------------

-- Experimental support for auto-scaling touch event positions

-- Call with true to make all touch listers event.x/y be scaled to user coordinates
-- Call with false to reset to default behaviour (event coords are world space)
-- Off by default.
-- This is quite a hack! It is recommened to use virtualResolution:getUserX()
-- or getLocalCoords() inside event listeners instead.
-- Note that getLocalCoords is from github.com/nickchops/MarmaladeQuickNodeUtility
--
-- Using scaleTouchEvents has the advantage that all touches become in user-space
-- with zero changes to code but it will be slower as it adds a function call and
-- some amount of comparisons and table lookups for every event that ever fires!
-- Why? Because the safest place to override x&y is on event listener calls, but
-- QEvent objects are reused (for performance) so need lots of testing to make
-- sure we dont repeatedly rescale. Ouch.
function virtualResolution:scaleTouchEvents(on)
    if not self.scaleTouch and on then
        self.handleEventWithListener = handleEventWithListener
        handleEventWithListener = virtualResolutionHandleEventWithListenerOverride
        self.scaleTouch = true
    elseif self.scaleTouch and not on then
        handleEventWithListener = self.handleEventWithListener
        self.scaleTouch = false
    end
end

function virtualResolutionHandleEventWithListenerOverride(event, listener)
    -- turn screen coords into user coords
    if event.name == "touch" then
        -- The same touch event object propagates down node chain. We have to flag to avoid
        -- transforming recursively! Also, the evnent objects get reused for began, moved and ended
        -- phases, so have to flag each separately.
        -- Would be nice to transform on QEvent creation, but would then have to change QSystems
        -- code that does node intersection testing
        
        --dbg.print("in override touch funtion. phase=" .. event.phase)
        local doTrans = true
        if event.scaledFlag == event.phase then
            if event.phase == "moved" then
                -- moved events get reused from frame to frame and node to node :s
                -- so need to determine when a new "cycle" starts
                if not event.target then --system event
                    if not event.movedSystem then
                        event.movedSystem = true
                        doTrans = false
                    end
                else
                    if not event.movedList then event.movedList = {} end
                    if not event.movedList[event.target.name] then
                        event.movedList[event.target.name] = true
                        doTrans = false
                    end
                end
            else
                doTrans = false
            end
        end
        
        if doTrans then
            --dbg.print("transforming touch '" .. event.phase .. "' x,y=(" .. event.x .. "," .. event.y .. ") ->")
            event.x = (event.x - virtualResolution.xOffset) / virtualResolution.scale
            event.y = (event.y - virtualResolution.yOffset) / virtualResolution.scale
            --dbg.print("scaled x,y=(" .. event.x .. "," .. event.y .. ")")
            event.scaledFlag = event.phase
        --else
        --    dbg.print("ignoring ready scaled touch '" .. event.phase .. "' x,y=(" .. event.x .. "," .. event.y .. ")")
        end
    end
    return virtualResolution.handleEventWithListener(event, listener)
end

-----------------------------------------------------------------------------

-- Getters for transforming between coord spaces

-- Scale a value manually from world to user space.
-- Recommended to use this for touches instead of using virtualResolution:scaleTouchEvents(true)
-- for performance/future proofing
function virtualResolution:getUserX(winX)
    return (winX - self.xOffset) / self.scale
end

function virtualResolution:getUserY(winY)
    return (winY - self.yOffset) / self.scale
end

function virtualResolution:userToWinSize(userSize)
    return userSize * self.scale
end

function virtualResolution:winToUserSize(winSize)
    return winSize / self.scale
end

-- Scale from user to world space.
-- Can use *instead of* virtualResolution:applyToScene(myScene)
-- You will then need to manually scale every value, including velocities etc.
-- e.g createNode(posx, posy) -> createNode(vr.x(posx), vr.y(posy))
-- Note that this may be useful if you want lots of control,
-- e.g. scale vector coords but not line widths. Useful for drawing things
-- like on screen controls using user coords but with crisp world space display

function virtualResolution:getWinX(userX)
    return userX * self.scale + self.xOffset
end

function virtualResolution:getWinY(userY)
    return userY * self.scale + self.yOffset
end

