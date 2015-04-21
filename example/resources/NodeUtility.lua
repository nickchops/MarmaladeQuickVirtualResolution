
-- Utility functions for working with Marmalade Quick Node objects
-- (C) Nick Smith 2014

function cancelTimersOnNode(node, recursive)
    for k,v in pairs(node.timers) do
        v:cancel()
    end
    if recursive then
        for k,child in pairs(node.children) do
            cancelTimersOnNode(child)
        end
    end
end

function cancelTweensOnNode(node, recursive)
    --Docs state to not loop though node.tweens manually, but we're doing it anyway!
    --NB: in SDK, tween:cancel() causes tween to be removed from node.tweens in an ipairs loop
    --We're relying on that being true - using our own ipairs loop here would cause errors.
    --Prob should also update tween:cancel in SDK to call break one it removes a tween
    --for a tiny bit of performance (or replace SDK's loop with index by id or somesuch).
    while node.tweens[1] do
        tween:cancel(node.tweens[1])
    end
    
    if recursive then
        for k,child in pairs(node.children) do
            cancelTweensOnNode(child)
        end
    end
end

-- Use this function to remove Quick nodes from the current scene
-- Can pass it to tween:to/from as the onComplete callback (onComplete is
-- automatically passed the owning node as a param)
-- Still need to manually nil any explicit handle we have afterwards
-- Often the nodes have no handle in a game, e.g. ones that were only ever
-- handled with local vars
-- Also cancels all timers and tweens as these would keep running until node
-- is garbage collected.
function destroyNode(node)
    cancelTimersOnNode(node)
    cancelTweensOnNode(node)
    if node.physics then physics:removeNode(node) end
    node:removeFromParent() --also sets parent's reference to this node to nil
    return nil -- calling myNode = destroyNode(myNode) sets ref to nil
               -- to match behaviour of node:removeFromParent()
end

-- Quick has no "director:pauseAllNodeTimers()" or equivalent for tweens - 
-- Use this to recursively find all children and pause them
function pauseNodesInTree(node)
    node:pauseTimers()
    node:pauseTweens()
    for k,child in pairs(node.children) do
        pauseNodesInTree(child)
    end
end

function resumeNodesInTree(node)
    node:resumeTimers()
    node:resumeTweens()
    for k,child in pairs(node.children) do
        resumeNodesInTree(child)
    end
end

-- Recursively kill tree of nodes. Top level node is optional
-- Will not nil any values pointing to the nodes, but useful for cleaning up
-- dynamically created nodes that only get tracked via the scene graph.
function destroyNodesInTree(node, destroyRoot)
    
    --NB: Docs say to not insert or remove while looping node.children,
    --but rules are there to break...!
    --Each eventual call to destroyNode() calls removeFromParent(), which finds
    --node in parent's .children array and uses table.remove.
    --For our loop, we can't use pairs() as order is not guaranteed. Can't use
    --ipairs as behaviour is undefined after table.remove during ipairs loop.
    --So, we use a manual loop and know that the SDK's .remove call will collapse
    --the tree meaning we don't need to increment the index.
    local i = 1
    while node.children[i] do
        --workaround to support VirtualResolution: don't delete the scalar node
        local destroyThisRoot = (node.children[i] ~= node.scalerRootNode)
        
        destroyNodesInTree(node.children[i], destroyThisRoot)
        if not destroyThisRoot then
            i = i + 1 --but we do increment if we didn't delete the node
        end
    end
    
    if destroyRoot then
        destroyNode(node)
        return nil --return nil allows user to call myNode = destroyNodesInTree(myNode, yes)
                   --convenient way to nil reference and matches removeFromParent() behaviour
    end
    
    --we could probably make this more efficient by traversing the other
    --way and calling removeChild instead of destroyNode -> removeFromParent...
end


----------------------------------------------------------------

-- Translating between parent and child coordspace positions

-- These were originally part of github.com/nickchops/MarmaladeQuickVirtualResolution
-- but they dont rely on the VirtualResolution mechanism at all so moved here.
-- They just recursively calculate world and local coords by following parent
-- references. If using VirtualResolution is a scalerRootNode then that will be included like
-- any other node. It's recommended to use these inside touch events instead of
-- virtualResolution:scaleTouchEvents - minimises work and avoids hacking
-- with the Quick engine.

-- get world coords of a node's x & y pos
function getWorldCoords(n)
    local worldX = n.x
    local worldY = n.y
    n = n.parent
    while n do
        worldX = worldX * n.xScale + n.x
        worldY = worldY * n.yScale + n.y
        n = n.parent
    end
    return worldX, worldY
end

function getWorldCoordX(n)
    local worldX = n.x
    n = n.parent
    while n do
        worldX = worldX * n.xScale + n.x
        n = n.parent
    end
    return worldX
end

function getWorldCoordY(n)
    local worldY = n.y
    n = n.parent
    while n do
        worldY = worldY * n.yScale + n.y
        n = n.parent
    end
    return worldY
end

-- localNode is the node whos x & y marks the origins of a local coord space
-- Use this to get position relative to the node of a world coord
function getLocalCoords(worldX, worldY, localNode)
    local localX = worldX
    local localY = worldY
    local n = localNode.parent
    while n do
        localX = (localX - n.x) / n.xScale
        localY = (localY - n.y) / n.yScale
        n = n.parent
    end
    return localX, localY
end


function FlickerFx(event)
    event.target:pauseTweens()
    event.target.flicker = true --for trailfx
    event.target.storeAlpha=event.target.alpha
    event.target.storeStroke=event.target.strokeAlpha
    event.target.alpha=event.target.flickerAlpha or 0
    event.target.strokeAlpha=event.target.flickerStrokeAlpha or 0
    event.target:addTimer(UnFlickerFx, 0.1, 1)
end

function UnFlickerFx(event)
    event.target.alpha=event.target.storeAlpha
    event.target.strokeAlpha=event.target.storeStroke
    event.target:resumeTweens()
    event.target.flicker = false
    event.target:addTimer(FlickerFx, math.random(event.target.flickerMin,event.target.flickerMax)/10, 1)
end

--------------------------------------------------------------------
-- scaling

-- TODO: In SDK itself, we should attach these to the Node type so can just do myNode:setDefaultSize() etc

-- Sprites are the size of the file image by default and xScale/yScale is realtive to that
-- You cant just set w and h on a sprite, its always the file size.
-- This allows you to set an absolute default size in pixels.
-- Then you can use setRelativeScale to set x/y scales relative to the size you set here.
function setDefaultSize(node, w, h, keepRatio, scaleNow)
    if keepRatio == nil then keepRatio = true end --only used if only one of w or h is specified
    if scaleNow == nil then scaleNow = true end  --apply scaling now. On by default
    node.defaultScaleX = 1
    node.defaultScaleY = 1
    node.defaultW = w
    node.defaultH = h
    if w then
        node.defaultScaleX = w/node.w
    end
    if h then
        node.defaultScaleY = h/node.h
    end
    if keepRatio then
        if node.defaultScaleY and not w then
            node.defaultScaleX = node.defaultScaleY
        end
        if node.defaultScaleX and not h then
            node.defaultScaleY = node.defaultScaleX
        end
    end
    if scaleNow then
        node.xScale = node.defaultScaleX
        node.yScale = node.defaultScaleY
    end
end

-- like above, but only one-off. setRelativeSize will ignore anything we set here
function setSize(node, w, h, keepRatio)
    if keepRatio == nil then keepRatio = true end --only used if only one of w or h is specified
    local wScale
    local hScale
    if w then
        wScale = w/node.w
        node.xScale = wScale
    end
    if h then
        hScale = h/node.h
        node.yScale = hScale
    end
    if keepRatio then
        if hScale and not wScale then
            node.xScale = hScale
        end
        if wScale and not hScale then
            node.yScale = wScale
        end
    end
end

function getScaledX(node, x)
    if node.defaultScaleX then
        return x*node.defaultScaleX
    else
        return x
    end
end

function getScaledY(node, y)
    if node.defaultScaleY then
        return y*node.defaultScaleY
    else
        return y
    end
end

function setRelativeScale(node, xScale, yScale)
    if xScale then
        if node.defaultScaleX then
            node.xScale = xScale*node.defaultScaleX
        else
            node.xScale = xScale
        end
    end
    if yScale then
        if node.defaultScaleY then
            node.yScale = yScale*node.defaultScaleY
        else
            node.yScale = yScale
        end
    end
end

function getWidth(node)
    return node.w*node.xScale
end

function getHeight(node)
    return node.h*node.yScale
end