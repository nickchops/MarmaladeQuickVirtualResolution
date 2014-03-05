
Flexible Virtual Resolution system for use with Marmalade Quick
(C) Nick Smith 2014

Implements a virtual resolution scaling system, with letterboxes that can
be drawn over. A singleton table scales a scene between user coord space &
screen/window space

You need a Marmalade license and Marmalade SDK 7.0 or newer to use this code
    www.madewithmarmalade.com

--------
Overview
--------

Set the size of the coordinate space you want to use for the scene, set the
scene and then it will silently scale everything up to screen size.
Can optionally scale touch events, but this has a performance hit and is
pretty hacky! Note that Quick always returns *world* coord touch events.

It is recommended to scale touches using:
	virtualResolution:getUserX(x) -> screen to user world coords
	getLocalCoords(worldX, worldY, localNode) -> screen to "local" coords -
		return value is relative to localNode

How it works:
It adds a node called "scalerRootNode" to the scene, applies transforms to
that and then overrides the scene node to add children to scalerRootNode
instead of itself.

Be careful if you use myScene.children. For example, if you loop through
myScene.children to destroy all visual nodes, you will also destroy the
scalerRootNode and cause havoc :) It's recommended to always have an
"origin" node in a scene, or use scene.children and explicitly ignore
scene.scalerRootNode.


----------
User Guide
----------

Basics
------

'virtualResolution' is a singleton table performs most tasks

virtualResolution:initialiseForUserCoordSpace(userSpaceW, userSpaceH)
   Call this first, with width and height of "user space", aka "virtual resolution"
   This will also get the window sizes and work out scaling and offset to apply

   Then create scenes with director:createScene(...

virtualResolution:setScene(myScene)
   Then call this for each scene you want to use virtual resolution on

virtualResolution:scaleTouchEvents(true)
   Optionally set this true to make event.x and event.y values be returned in
   user space rather than window/screen space. Not recommend as it reduces
   performance of general event handling and is rather hacky. But good for
   some quick testing.

virtualResolution:getUserX(event.x)
virtualResolution:getUserY(event.y)
   If not using scaleTouchEvents(true), use these in event listeners to
   translate world event positions to user space ones. Useful for touch!

   For getters, its recommended to use shortcuts like:
vr = virtualResolution
vr.x = vr.getUserX
vr.y = vr.getUserY

   then you can do
function myTouchListener(event)
    userX = vr.x(event.x)
    ...
end


Advanced
--------

virtualResolution:getWinX(userX)
virtualResolution:getWinX(userY)
   Use these to translate user space to world space. Useful if you have NOT
   called virtualResolution:setScene(myScene) and want to scale everything
   manually.

virtualResolution:updateWindowSize()
   Call this is the window size changes (e.g. on desktop) to re-configure

virtualResolution:initialiseForUserCoordSpace(...)
   Call this again if you want to change virtual resolution!

myScene.scalerRootNode
   This node is added to a scene by virtualResolution:setScene() and does
   the scaling. You can play with it manually if you want :)

virtualResolution:releaseScene(myScene, [false])
   Call this when you are done with a scene. It will remove the scalerRootNode
   that is silently doing the transforms. By default, any children of the scene
   will be "kept" as they get moved from being children of the scaling node to
   the scene itself. Pass false as the second param to stop this and remove any
   children from the scene! If just destroying the scene, you probably don't
   need this at all. There's No need to call this on transitioning from a scene

myScene:addChildNoTrans(node)
   Calling virtualResolution:setScene() will cause the scenes :addChild()
   calls to be redirected to myScene.scalerRootNode:addChild(). The original
   method is "backed-up" via .addChildNoTrans. So, you can use
   myScene:addChildNoTrans(node) to bypass virtual resolution and add nodes
   that are "in window space".

   
TODO: add built in options for letterbox/borders

Provided under the MIT license:

/*
 * (C) 2013-2014 Nick Smith.
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

Hack away and re-use code for your own projects :)
