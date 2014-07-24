
 --[[
    (C) Nick Smith 2014
    Flexible virtual resolution system for use with Marmalade Quick
    
    Implements a virtual resolution scaling system, with letterbox areas that
    can just be drawn over. A singleton table scales a scene between user coord
    space & screen/window space.
  
    Overview:
    Set the size of the coordinate space you want to use for the scene, then
    pass references to any scenes you want to be scaled and then it will
    silently scale everything up to screen size.
    
    Can optionally:
    - "override" the window size. Setting window smaller than the real window
      will result in extra border area around all 4 sides
    - use "nearestMultiple" which overrides window size to be largest size
      that is both a multiple of the user size and <= screen size. This
      scales up but makes sure that every userspace pixel translates to an
      integer value so the result is pixel-perfect, e.g. 1 pixel -> 2/3/4/etc.
      pixels, rather than 1 pixel -> 1.5/2.7/3.1/etc. pixels.
      - ignoreMultipleIfTooSmall. You can use this with nearestMultiple as a
        gating factor. If the scaled up size would be less than this fraction
        of the screen W or H (whichever is the control axis), then
        nearestMultiple is ignored.
    - Use forceScale which sets a fraction (0->1) of the width or height
      (whichever ends up being the most "full") to scale up to. Ensures
      a border of this amount on all sides. Ignored if nearestMultiple
      is set and succeeds, but used if nearestMultiple is set but fails
      due to ignoreMultipleIfTooSmall.
    - scale touch events, but this has a performance hit and is pretty hacky
      so not recommended!
      
    Note that Quick always returns *world* coord touch events so you will
    usually want to scale those.
  
    It is recommended to scale touches using either:
        virtualResolution:getUserX(x) -> screen to user "world" coords
    or
        getLocalCoords(worldX, worldY, localNode) -> screen to "local" coords
            Here, the returned values are relative to localNode.
            More powerful as it can go any depth down a child tree.
            This is in https://github.com/nickchops/MarmaladeQuickNodeUtility
            - not part of VirtualResolution.
  
    How it all works:
    When you call applyToScene(), it adds a node called "scalerRootNode" to the
    scene, applies transforms to that and then overrides the scene node to add
    children to scalerRootNode instead of to itself.
  
    Be careful if you every use myScene.children. For example, if looping 
    through myScene.children to destroy all visual nodes, you will also
    destroy the scalerRootNode and cause havock :) It's recommeneded to always
    have an "origin" node in a scene (avoids general issues with scenes), or
    if not then when using scene.children make sure you explicitly ignore
    scene.scalerRootNode.
]]--

virtualResolution = {}


--[[ To use:

--Basics

virtualResolution:initialiseForUserCoordSpace(userSpaceW, userSpaceH)
-- Call this first, with width and height of "user space", aka "virtual
-- resolution". This will also get the window sizes and work out scaling
-- and offset to apply

Or, for more control, use:
initialise(vals)
-- Uses {} format for ease of use :) e.g. call it like this:
--  virtualResolution:initialiseForUserCoordSpace{userSpaceW=1200, userSpaceH=300}
--
-- Optional:
-- - Window size to scale up to is usually autodetected. You can override this
--   and force the window size using windowOverrideW and windowOverrideH. e.g.
--   Set this to half window real size for the output to be small and centered
--   with lots of black space around it. Useful is you want explicit sizes for
--   areas in the letterboxes where on-screen controls will go.
--
-- - Setting nearestMultiple=true will cause the window size values to be the
--   largest integer multiples of the userspace sizes that will fit on the
--   screen. e.g. if app is in landscape, user height is 300 and screen height
--   is 700, window height will be set to 600. This means every pixel maps to
--   exactly 2 pixels, with some additional padding added. Useful if you
--   want "pixel-perfect" upscaling, but will increase letterboxing.
--   nearestMultiple is ignored if windowOverrideW or windowOverrideH is set.

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

virtualResolution:update()
-- Call this if the window size changes - eg on desktop stretch or device
-- rotation - to re-configure everything

virtualResolution:initialise(...)
-- Call this again if you want to change userspace resolution

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

--TODO add built in options for drawing fancy letterbox/borders

-----------------------------------------

-- Public setup functions

--simple version
function virtualResolution:initialiseForUserCoordSpace(userSpaceW, userSpaceH)
    virtualResolution:initialise{userSpaceW, userSpaceH}
end

--full version
function virtualResolution:initialise(vals)
    self.userW = vals.userSpaceW
    self.userH = vals.userSpaceH
    self.windowOverrideW = vals.windowOverrideW
    self.windowOverrideH = vals.windowOverrideH
    self.nearestMultiple = vals.nearestMultiple
    self.ignoreMultipleIfTooSmall = vals.ignoreMultipleIfTooSmall
    self.forceScale = vals.forceScale
    self.maxScreenW = vals.maxScreenW
    self.maxScreenH = vals.maxScreenH
    self:update()
end

function virtualResolution:update()
    if not self.userW then
        dbg.print("must call initialise or initialiseForUserCoordSpace before update")
        return
    end
    
    self.winW = self.windowOverrideW or director.displayWidth
    self.winH = self.windowOverrideH or director.displayHeight
    
    self.winAspect = self.winW / self.winH
    self.userAspect = self.userW / self.userH
    
    if self.winAspect < self.userAspect then
        self.scaleIn = "width"
        self.scale = self.winW / self.userW
        self:doMultipleAndOffset()
        self.yOffset = self.yOffset + (self.winH - self.userH*self.scale) / 2
    else
        self.scaleIn = "height"
        self.scale = self.winH / self.userH
        self:doMultipleAndOffset()
        self.xOffset = self.xOffset + (self.winW - self.userW*self.scale) / 2
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
        dbg.assert(false, "virtualResolution:applyToScene called before initialise or initialiseForUserCoordSpace")
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
   
    if scene.scalerRootNode then
        dbg.print("virtualResolution:applyToScene called for scene already using virtual resolution - updating values")
        scene.scalerRootNode.x=self.xOffset
        scene.scalerRootNode.y=self.yOffset
        scene.scalerRootNode.xScale=self.scale
        scene.scalerRootNode.yScale = self.scale
    else
        scene.scalerRootNode = director:createNode({x=self.xOffset, y=self.yOffset, xScale=self.scale, yScale = self.scale})
        if not director.addNodesToScene or scene ~= director:getCurrentScene() then
            scene:addChild(scalerRootNode) --already added via createNode() above otherwise
        end
        
        -- Override scene:addChild() to call scene.scalerRootNode:addChild()
        -- Note that we cant just do scene.addChild = scene.scalerRootNode.addChild
        -- because those .addChild functions are the same actual function value! It's the
        -- "self" value passed implicitly via : mechanism that determins which node is used!
        scene.addChildNoTrans = scene.addChild -- keep a backup so user can still add "window space" nodes
        scene.addChild = virtualResolutionSceneAddChildOverride
        
        -- note that scene:addChild() is called internally via director:addNodeToLists()
        -- on director:createXXX() calls if director.addNodesToScene is true
    end
end

---------------------------
-- internal setup functions

function virtualResolution:doMultipleAndOffset()
    if not (windowOverrideW or windowOverrideH) then
        local scaledDiff
        local nearestMultipleFailed = false
        
        -- optionally adjust scaling to next lowest integer value
        if self.nearestMultiple then
            self.scale = math.floor(self.scale)
            self.winW = self.scale * self.userW
            self.winH = self.scale * self.userH
            
            if self.ignoreMultipleIfTooSmall then 
                if self.scaleIn == "width" then
                    scaledDiff = self.winW / director.displayWidth
                else
                    scaledDiff = self.winH / director.displayHeight
                end
                
                if scaledDiff < self.ignoreMultipleIfTooSmall then
                    nearestMultipleFailed = true
                end
            end
        end
        
        -- optionally set to specific scale (ignored if nearest multiple succeeded)
        if self.forceScale and (nearestMultipleFailed or not self.nearestMultiple) then
            -- scale so view fills given fraction of the sclaing axis (width or height)
            if self.scaleIn == "width" then
                self.winW = self.forceScale * director.displayWidth
                self.scale = self.winW/self.userW
                self.winH = self.scale * self.userH
            else
                self.winH = self.forceScale * director.displayHeight
                self.scale = self.winH/self.userH
                self.winW = self.scale * self.userW
            end
        
        -- optionally lock to max width or heigh fractions (0->1) if greater than those
        else
            if self.maxScreenW then
                scaledDiff = self.winW / director.displayWidth
                if scaledDiff > self.maxScreenW then
                    self.winW = self.maxScreenW * director.displayWidth
                    self.scale = self.winW/self.userW
                    self.winH = self.scale * self.userH
                end
            end
            if self.maxScreenH then
                scaledDiff = self.winH / director.displayHeight
                if scaledDiff > self.maxScreenH then
                    self.winH = self.maxScreenH * director.displayHeight
                    self.scale = self.winH/self.userH
                    self.winW = self.scale * self.userW
                end
            end
        end
    end
    
    self.xOffset = (director.displayWidth - self.winW)/2 --zero if not forcing window size
    self.yOffset = (director.displayHeight - self.winH)/2
end


function virtualResolutionSceneAddChildOverride(self, n)
    self.scalerRootNode:addChild(n)
end
--------------------------------------
--Public release function

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

