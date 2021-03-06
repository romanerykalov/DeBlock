/*
 * This file is part of Deblock.
 *
 *  Deblock is open software: you can use or modify it under the
 *  terms of the Java Research License or optionally a more
 *  permissive Commercial License.
 *
 *  Deblock is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 *
 *  You should have received a copy of the Java Research License
 *  along with Deblock in the file named 'COPYING'.
 *  If not, see <http://stuff.lhunath.com/COPYING>.
 */

//
//  GameLayer.h
//  Deblock
//
//  Created by Maarten Billemont on 19/10/08.
//  Copyright, lhunath (Maarten Billemont) 2008. All rights reserved.
//


#import "SkyLayer.h"
#import "FieldLayer.h"

typedef enum DbEndReason {
    DbEndReasonStopped,
    DbEndReasonGameOver,
    DbEndReasonNextField,
} DbEndReason;


@interface GameLayer : CCLayer <Resettable> {

    BOOL                                                _paused;
    BOOL                                                _running;
    DbEndReason                                         _endReason;

    SkyLayer                                            *_skyLayer;
    FieldLayer                                          *_fieldLayer;
    CCLayer                                             *_fieldScroller;

    CCAction                                            *_shakeAction;

    ccTime                                              _penaltyInterval;
    ccTime                                              _remainingPenaltyTime;
}

@property (nonatomic, readwrite) BOOL                   paused;
@property (nonatomic, readwrite) BOOL                   running;

@property (nonatomic, readonly, retain) SkyLayer                *skyLayer;
@property (nonatomic, readonly, retain) FieldLayer              *fieldLayer;

- (void)shake;

- (void)newGameWithMode:(DbMode)gameMode;
- (void)startGame;
- (void)stopGame:(DbEndReason)reason;

- (void)started;
- (void)stopped;

- (void)levelRedo;

@end
