Marmalade Quick Virtual Resolution helper
=========================================

Flexible Virtual Resolution system for use with Marmalade Quick

Implements a virtual resolution scaling system, with letterboxes that can
be drawn over. A singleton table scales a scene between user coord space &
screen/window space

You need a Marmalade license and Marmalade SDK 7.0 or newer to use this code:
    www.madewithmarmalade.com


Overview
--------

Set the size of the coordinate space you want to use for the scene, set the
scene and then it will silently scale everything up to screen size.
Can optionally scale touch events, but this has a performance hit and is
pretty hacky!

Note that Quick always returns *world* coord touch events so it is
recommended to scale touches using either:

    virtualResolution:getUserX(x)
        -> screen to user world coords

or:

    getLocalCoords(worldX, worldY, localNode)
        -> screen to "local" coords - return value is relative to localNode
        NB: from https://github.com/nickchops/MarmaladeQuickNodeUtility

*How it works*

It adds a node called "scalerRootNode" to the scene, applies transforms to
that and then overrides the scene node to add children to scalerRootNode
instead of itself.

Be careful if you use myScene.children. For example, if you loop through
myScene.children to destroy all visual nodes, you will also destroy the
scalerRootNode and cause havoc :) It's recommended to always have an
"origin" node in a scene, or use scene.children and explicitly ignore
scene.scalerRootNode.



User Guide
----------

### Quick start

To start, you need to pick a "user space" screen size that your game's logic
will use. e.g. decide to use 960x640, then call:

    virtualResolution:initialiseForUserCoordSpace(960,640)

Then, once you have created a scene, but before adding any nodes to it, call
this to make a scene actually use the VR system:

    virtualResolution:applyToScene(myScene)

You can call applyToScene for multiple scenes at the same time. There's no need to
turn previous scenes off.

From now, you can do all game logic as if the screen was 960x640. VR will work
automatically, whether you just use director:createXXX and leave nodes to be
added to the scene, or explicitly call myScene:addChild(myNode) There may be
a "letterbox" area at the top or bottom depending on screen aspect ratio. Quick
will continue drawing to the letterbox area. You likely want to cover those
areas by drawing over them (see below) - just having black boxes is usually
frowned upon by publishers and stores.

You may want to draw overlays, or other things into the letterbox areas in user
space, so you might want something like:

    userScreenWidth = virtualResolution:winToUserSize(director.displayWidth)
    userScreenHeight = virtualResolution:winToUserSize(director.displayHeight)

The values above will include the letter box, so for example might be 1000 and
640 if the device aspect ratio is wider than user space. You can then figure
out the letterbox sizes and position.

Note that Quick always gives touch event positions in world/screen coordinates.
So, you can use the following inside touch events:

    virtualResolution:getUserX(event.x)
    virtualResolution:getUserY(event.y)

If you want to add a node to the scene and *not* scale it, you can do:

    myNode = director:createXXX(...)
    myScene:addChildNoTrans(myNode)

You could use the above to draw the letterbox overlays in screen space, to
add overlay controls, or to render text that you don't want scaled.


### Basic functions

**virtualResolution** is a singleton table performs most tasks

**virtualResolution:initialiseForUserCoordSpace(userSpaceW, userSpaceH)**

- Call this first, with width and height of "user space", aka "virtual resolution"
  This will also get the window sizes and work out scaling and offset to apply

  Then create scenes with director:createScene(...

**virtualResolution:initialise(vals)**

- Use this version for more options.
  Uses {} format for ease of use :) e.g. call it like this:

	virtualResolution:initialiseForUserCoordSpace{userSpaceW=1200, userSpaceH=300}

**virtualResolution:applyToScene(myScene)**

- Then call this for each scene you want to use virtual resolution on

**virtualResolution:getUserX(event.x)** and **virtualResolution:getUserY(event.y)**

- If not using scaleTouchEvents (see advanced), use these in event listeners to
  translate world event positions to user space ones. Useful for touch!

  For getters, its recommended to use shortcuts like:

        vr = virtualResolution
        vr.x = vr.getUserX
        vr.y = vr.getUserY

  then you can do:

        function myTouchListener(event)
            userX = vr.x(event.x)
            ...
	    end


### Advanced

**virtualResolution:scaleTouchEvents(true)**

- Optionally set this true to make event.x and event.y values be returned in user space
  rather than window/screen space. Not recommend as it reduces performance of general
  event handling and is rather hacky. But good for some quick testing.


**virtualResolution:getWinX(userX)** and **virtualResolution:getWinX(userY)**

- Use these to translate user space to world space. Useful if you have NOT
  called virtualResolution:applyToScene(myScene) and want to scale everything
  manually.

**virtualResolution:update()**

- Call this if the window size changes (e.g. on desktop) to re-configure

**virtualResolution:initialise(...)**

- Call this again if you want to change virtual resolution!

**virtualResolution:applyToScene(myScene)**

- If the window size changes, call this again to actually update the scene scaling

**myScene.scalerRootNode**

- This node is added to a scene by virtualResolution:applyToScene() and does
  the scaling. You can play with it manually if you want :)

**virtualResolution:releaseScene(myScene, [false])**

- Call this when you are done with a scene. It will remove the scalerRootNode
  that is silently doing the transforms. By default, any children of the scene
  will be "kept" as they get moved from being children of the scaling node to the scene
  itself. Pass false as the second param to stop this and remove any children from the
  scene! If just destroying the scene, you probably don't need this at all. There's no
  need to call this on transitioning from a scene.

**myScene:addChildNoTrans(node)**

- Calling virtualResolution:applyToScene() will cause the scenes :addChild()
  calls to be redirected to myScene.scalerRootNode:addChild(). The original
  method is "backed-up" via .addChildNoTrans. So, you can use
  myScene:addChildNoTrans(node) to bypass virtual resolution and add nodes
  that are "in window space".


**TODO:** add built in options for letterbox/borders


------------------------------------------------------------------------------------------
(C) 2013-2014 Nick Smith.

All code is provided under the MIT license unless stated otherwise:

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
