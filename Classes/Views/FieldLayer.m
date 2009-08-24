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
//  CityLayer.m
//  Deblock
//
//  Created by Maarten Billemont on 26/10/08.
//  Copyright 2008-2009, lhunath (Maarten Billemont). All rights reserved.
//

#import "FieldLayer.h"
#import "DeblockAppDelegate.h"

#define kAllGridLevel   20
#define kMinColumns     5
#define kMaxColumns     10
#define kMinRows        3
#define kMaxRows        8

@interface FieldLayer (Private)

- (NSInteger)destroyBlock:(BlockLayer *)aBlock forced:(BOOL)forced;
- (void)destroySingleBlockAtRow:(NSInteger)row col:(NSInteger)col;

- (void)startDropping;
- (BOOL)dropBlockAtRow:(NSInteger)row col:(NSInteger)col;
- (void)doneDroppingBlock:(BlockLayer *)block;
- (void)droppingFinished;

- (void)startCollapsing;
- (BOOL)collapseBlocksAtCol:(NSInteger)col;
- (void)doneCollapsingBlock:(BlockLayer *)block;
- (void)collapsingFinished;

@end


@implementation FieldLayer

@synthesize locked;


-(id) init {
    
    if (!(self = [super init]))
		return self;
    
    blockPadding    = 0;
    locked          = YES;
    
    return self;
}


-(void) registerWithTouchDispatcher {
    
	[[TouchDispatcher sharedDispatcher] addTargetedDelegate:self priority:0 swallowsTouches:YES];
}



-(void) reset {

    // Clean up.
    [self stopAllActions];
    
    if (blockGrid) {
        for (NSInteger row = 0; row < blockRows; ++row) {
            for (NSInteger col = 0; col < blockColumns; ++col) {
                BlockLayer *block = blockGrid[row][col];
                if (!block)
                    continue;
                
                [self removeChild:block cleanup:YES];
                blockGrid[row][col] = nil;
                [block release];
            }
            free(blockGrid[row]);
        }
        free(blockGrid);
    }

    // Level-based field parameters.
    blockColumns    = fmaxf(fminf(kMaxColumns * [[DMConfig get].level intValue] / kAllGridLevel, kMaxColumns), kMinColumns);
    blockRows       = fmaxf(fminf(kMaxColumns * [[DMConfig get].level intValue] / kAllGridLevel, kMaxRows), kMinColumns);
    gravityRow      = 0;
    gravityColumn   = blockColumns / 2;
    blockGrid = malloc(sizeof(BlockLayer **) * blockRows);
    
    // Build field of blocks.
    CGSize blockSize        = CGSizeMake((self.contentSize.width   - blockPadding) / blockColumns  - blockPadding,
                                         (self.contentSize.height  - blockPadding) / blockRows     - blockPadding);
    
    for (NSInteger row = 0; row < blockRows; ++row) {
        blockGrid[row] = malloc(sizeof(BlockLayer *) * blockColumns);
        
        for (NSInteger col = 0; col < blockColumns; ++col) {
            
            BlockLayer *block = [[BlockLayer alloc] initWithBlockSize:blockSize];
            block.position = ccp(col * (blockSize.width     + blockPadding) + blockPadding,
                                 row * (blockSize.height    + blockPadding) + blockPadding);
            
            [self addChild:block];
            blockGrid[row][col] = [block retain];
            [block release];
        }
    }
}


- (BlockLayer *)blockAtRow:(NSInteger)aRow col:(NSInteger)aCol {
    
    if (aRow < 0 || aCol < 0)
        return nil;
    if (aRow >= blockRows || aCol >= blockColumns)
        return nil;
    
    return blockGrid[aRow][aCol];
}


- (BlockLayer *)blockAtTargetRow:(NSInteger)aRow col:(NSInteger)aCol {
    
    for (NSInteger row = 0; row < blockRows; ++row)
        for (NSInteger col = 0; col < blockColumns; ++col) {
            BlockLayer *block = blockGrid[row][col];
            if (!block)
                continue;
            
            if (block.targetRow == aRow && block.targetCol == aCol)
                return block;
        }
    
    return nil;
}


- (NSArray *)blocksInRow:(NSInteger)aRow {

    NSMutableArray *blocks = [NSMutableArray arrayWithCapacity:blockColumns];
    for (NSInteger col = 0; col < blockColumns; ++col) {
        BlockLayer *block = blockGrid[aRow][col];
        if (block)
            [blocks addObject:block];
    }
    
    return blocks;
}


- (NSArray *)blocksInCol:(NSInteger)aCol {
    
    NSMutableArray *blocks = [NSMutableArray arrayWithCapacity:blockRows];
    for (NSInteger row = 0; row < blockRows; ++row) {
        BlockLayer *block = blockGrid[row][aCol];
        if (block)
            [blocks addObject:block];
    }
    
    return blocks;
}


- (NSArray *)blocksInTargetRow:(NSInteger)aRow {
    
    NSMutableArray *blocks = [NSMutableArray arrayWithCapacity:blockColumns];
    for (NSInteger col = 0; col < blockColumns; ++col) {
        BlockLayer *block = [self blockAtTargetRow:aRow col:col];
        if (block)
            [blocks addObject:block];
    }
    
    return blocks;
}


- (NSArray *)blocksInTargetCol:(NSInteger)aCol {
    
    NSMutableArray *blocks = [NSMutableArray arrayWithCapacity:blockRows];
    for (NSInteger row = 0; row < blockRows; ++row) {
        BlockLayer *block = [self blockAtTargetRow:row col:aCol];
        if (block)
            [blocks addObject:block];
    }
    
    return blocks;
}


- (NSArray *)findLinkedBlocksOfBlockAtRow:(NSInteger)aRow col:(NSInteger)aCol {
    
    DMBlockType type = [self blockAtRow:aRow col:aCol].type;
    
    // Find all neighbouring blocks of the same type.
    NSMutableArray *linkedBlocks = [NSMutableArray arrayWithCapacity:4];
    for (NSInteger r = aRow - 1; r <= aRow + 1; ++r) {
        BlockLayer *block = [self blockAtRow:r col:aCol];
        if (block == nil || r == aRow)
            // Bad block, ignore.
            continue;
        
        if (block.type == type)
            [linkedBlocks addObject:block];
    }
    for (NSInteger c = aCol - 1; c <= aCol + 1; ++c) {
        BlockLayer *block = [self blockAtRow:aRow col:c];
        if (block == nil || c == aCol)
            // Bad block, ignore.
            continue;
        
        if (block.type == type)
            [linkedBlocks addObject:block];
    }
    
    return linkedBlocks;
}


- (BOOL)findPositionOfBlock:(BlockLayer *)aBlock toRow:(NSInteger *)aRow col:(NSInteger *)aCol {
    
    for (NSInteger row = 0; row < blockRows; ++row)
        for (NSInteger col = 0; col < blockColumns; ++col)
            if ([self blockAtRow:row col:col] == aBlock) {
                if (aRow)
                    *aRow = row;
                if (aCol)
                    *aCol = col;
                
                return YES;
            }

    return NO;
}

- (void)getPositionOfBlock:(BlockLayer *)aBlock toRow:(NSInteger *)aRow col:(NSInteger *)aCol {

    if (![self findPositionOfBlock:aBlock toRow:aRow col:aCol])
        [NSException raise:NSInternalInconsistencyException format:@"Given block is not in the field."];
}


- (void)setPositionOfBlock:(BlockLayer *)aBlock toRow:(NSInteger)aRow col:(NSInteger)aCol {
    
    // By default, aBlock's old grid location must be unset (no more block there).
    BlockLayer *oldBlock = nil;
    
    BlockLayer *block = [self blockAtRow:aRow col:aCol];
    if (block) {
        if (block == aBlock)
            // Block already at its target destination.
            return;
        
        else if (block.moving)
            // However, if aBlock lands on a spot where another block is still moving from, back the other block up
            // to aBlock's old grid location so that it still remains in the grid and can still be found by any search operation.
            // When this other block is done moving it will unset this position itself (or trigger this behaviour again).
            oldBlock = block;
        else
            [NSException raise:NSInternalInconsistencyException format:@"Tried to set a block to a position that is occupied."];
    }
    
    NSInteger row, col;
    if ([self findPositionOfBlock:aBlock toRow:&row col:&col])
        blockGrid[row][col] = oldBlock;
    
    blockGrid[aRow][aCol] = aBlock;
}


- (void)destroyBlock:(BlockLayer *)aBlock {
    
    locked = YES;

    CGPoint blockPoint = aBlock.position;
    blockPoint.x += aBlock.contentSize.width / 2.0f;
    blockPoint.y += aBlock.contentSize.height;
    
    NSInteger destroyedBlocks = [self destroyBlock:aBlock forced:NO];
    NSInteger points = powf(destroyedBlocks, 2);
    if (points) {
        [DMConfig get].levelScore = [NSNumber numberWithInt:[[DMConfig get].levelScore intValue] + points];
        [[DeblockAppDelegate get].hudLayer updateHudWithScore: points];
        [self message:[NSString stringWithFormat:@"%+d", points] at:blockPoint];
    }
    
    [self performSelector:@selector(startDropping) withObject:nil afterDelay:0.5f];
}


- (NSInteger)destroyBlock:(BlockLayer *)aBlock forced:(BOOL)forced {
    
    if (aBlock.destroyed)
        // Already destroyed.
        return 0;

    // Find the position of the block to destroy.
    NSInteger row, col;
    [self getPositionOfBlock:aBlock toRow:&row col:&col];
    
    NSArray *linkedBlocks = [self findLinkedBlocksOfBlockAtRow:row col:col];
    if (!forced && ![linkedBlocks count])
        // No blocks linked, cannot destroy.
        return 0;
    
    // Destroy this block.
    [self destroySingleBlockAtRow:(NSInteger)row col:(NSInteger)col];
    
    // Destroy all linked blocks.
    NSUInteger destroyedBlocks = 1;
    for (BlockLayer *linkedBlock in linkedBlocks)
        destroyedBlocks += [self destroyBlock:linkedBlock forced:YES];
    
    return destroyedBlocks;
}


- (void)destroySingleBlockAtRow:(NSInteger)row col:(NSInteger)col {

    BlockLayer *block = blockGrid[row][col];
    if (!block)
        return;
    
    block.destroyed    = YES;
    [self reorderChild:block z:1];
    [block crumble];
    [block release];
    
    blockGrid[row][col] = nil;
}


- (void)startDropping {
    
    for (NSInteger row = 0; row < blockRows; ++row)
        for (NSInteger col = 0; col < blockColumns; ++col) {
            blockGrid[row][col].targetRow = row;
            blockGrid[row][col].targetCol = col;
        }
    
    BOOL anyBlockDropping = NO;
    for (NSInteger col = 0; col < blockColumns; ++col) {
        for (NSInteger row = gravityRow + 1; row < blockRows; ++row)
            anyBlockDropping |= [self dropBlockAtRow:row col:col];
        for (NSInteger row = gravityRow - 1; row >= 0; --row)
            anyBlockDropping |= [self dropBlockAtRow:row col:col];
    }
    
    if (!anyBlockDropping)
        // No blocks are dropping => dropping blocks is done.
        [self droppingFinished];
}


- (BOOL)dropBlockAtRow:(NSInteger)row col:(NSInteger)col {
    
    BlockLayer *block = [self blockAtRow:row col:col];
    if (!block || block.moving)
        // No block here or block already moving.
        return NO;
    
    
    NSInteger gravityRowDirection = gravityRow - row;
    if (gravityRowDirection == 0)
        // Hit the gravity "floor", stop dropping.
        return NO;
    gravityRowDirection /= fabsf(gravityRowDirection);
    
    // Row dropping.
    block.targetRow = row;
    while (YES) {
        if (block.targetRow == gravityRow)
            // Hit the gravity "floor", stop dropping.
            break;
        
        if ([self blockAtTargetRow:block.targetRow + gravityRowDirection col:block.targetCol])
            // Hit a block, stop dropping.
            break;
        
        block.targetRow += gravityRowDirection;
    }
    if (block.targetRow == row)
        // This block is already at its target, no moving needs to be done.
        return NO;
    
    CGFloat dropHeight = fabsf(row - block.targetRow) * (block.contentSize.height + blockPadding) * gravityRowDirection;
    ccTime duration = 0.3f * fabsf(dropHeight) / 100.0f;
    
    [block runAction:block.moveAction = [Sequence actions:
                                         [EaseSineIn actionWithAction:
                                          [MoveBy actionWithDuration:duration position:ccp(0, dropHeight)]],
                                         [CallFunc actionWithTarget:block selector:@selector(notifyDropped)],
                                         [EaseSineIn actionWithAction:
                                          [MoveBy actionWithDuration:duration / 3 position:ccp(0, -dropHeight / 20)]],
                                         [EaseSineIn actionWithAction:
                                          [MoveBy actionWithDuration:duration / 3 position:ccp(0, dropHeight / 20)]],
                                         [EaseSineIn actionWithAction:
                                          [MoveBy actionWithDuration:duration / 6 position:ccp(0, -dropHeight / 40)]],
                                         [EaseSineIn actionWithAction:
                                          [MoveBy actionWithDuration:duration / 6 position:ccp(0, dropHeight / 40)]],
                                         [CallFuncN actionWithTarget:self selector:@selector(doneDroppingBlock:)],
                                         nil]];
    
    return YES;
}


- (void)doneDroppingBlock:(BlockLayer *)block {
    
    [self setPositionOfBlock:block toRow:block.targetRow col:block.targetCol];
    
    [block stopAction:block.moveAction];
    block.moveAction = nil;
    
    BOOL allDoneDropping = YES;
    for (NSInteger row = 0; row < blockRows && allDoneDropping; ++row)
        for (NSInteger col = 0; col < blockColumns && allDoneDropping; ++col)
            if ([self blockAtRow:row col:col].moving) {
                allDoneDropping = NO;
            }
    
    if (allDoneDropping)
        [self droppingFinished];
}


- (void)droppingFinished {
    
    [self startCollapsing];
}


- (void)startCollapsing {
    
    BOOL anyBlockCollapsing = NO;
    for (NSInteger col = gravityColumn + 1; col < blockColumns; ++col)
        anyBlockCollapsing |= [self collapseBlocksAtCol:col];
    for (NSInteger col = gravityColumn - 1; col >= 0; --col)
        anyBlockCollapsing |= [self collapseBlocksAtCol:col];

    if (!anyBlockCollapsing)
        // No blocks are collapsing => collapsing blocks is done.
        [self collapsingFinished];
}


- (BOOL)collapseBlocksAtCol:(NSInteger)col {

    
    NSInteger gravityColDirection = gravityColumn - col;
    if (gravityColDirection == 0)
        // Hit the gravity "wall", stop collapsing.
        return NO;
    gravityColDirection /= fabsf(gravityColDirection);

    // Column collapsing.
    NSInteger targetCol = col;
    while (YES) {
        if (targetCol == gravityColumn)
            // Hit the gravity "wall", stop collapsing.
            break;
        
        if ([[self blocksInTargetCol:targetCol + gravityColDirection] count])
            // Hit a non-empty column, stop collapsing.
            break;
        
        targetCol += gravityColDirection;
    }
    if (targetCol == col)
        // This column is already at its target, no moving needs to be done.
        return NO;

    BOOL anyBlockCollapsing = NO;
    for (NSInteger row = 0; row < blockRows; ++row) {
        BlockLayer *block = [self blockAtRow:row col:col];
        if (!block || block.moving)
            // No block here or block already moving.
            continue;
        
        
        block.targetCol = targetCol;
        CGFloat dropWidth = fabsf(col - block.targetCol) * (block.contentSize.width + blockPadding) * gravityColDirection;
        
        [block runAction:block.moveAction = [[Sequence alloc] initOne:[MoveBy actionWithDuration:0.3f position:ccp(dropWidth, 0)]
                                                                  two:[CallFuncN actionWithTarget:self selector:@selector(doneCollapsingBlock:)]]];
        anyBlockCollapsing = YES;
    }
    
    return anyBlockCollapsing;
}


- (void)doneCollapsingBlock:(BlockLayer *)block {
    
    [self setPositionOfBlock:block toRow:block.targetRow col:block.targetCol];
    
    [block stopAction:block.moveAction];
    block.moveAction = nil;
    [block notifyCollapsed];
    
    BOOL allDoneCollapsing = YES;
    for (NSInteger row = 0; row < blockRows && allDoneCollapsing; ++row)
        for (NSInteger col = 0; col < blockColumns && allDoneCollapsing; ++col)
            if ([self blockAtRow:row col:col].moving)
                allDoneCollapsing = NO;
    
    if (allDoneCollapsing)
        [self collapsingFinished];
}


- (void)collapsingFinished {

    NSUInteger blocksLeft = 0, linksLeft = 0;
    for (NSInteger row = 0; row < blockRows; ++row)
        for (NSInteger col = 0; col < blockColumns; ++col) {
            BlockLayer *block = blockGrid[row][col];
            if (!block)
                continue;
            
            ++blocksLeft;
            if ([[self findLinkedBlocksOfBlockAtRow:row col:col] count])
                ++linksLeft;
        }
    
    if (!linksLeft) {
        DbEndReason endReason = DbEndReasonNextField;
        NSInteger points = [[DMConfig get].levelScore intValue];
        NSInteger bonusPoints = 0;
        
        if (!blocksLeft) {
            // No blocks left -> flawless finish.
            [[DeblockAppDelegate get].uiLayer message:@"Flawless!"];
            [self message:[NSString stringWithFormat:@"%+d", points]
                       at:ccp(self.contentSize.width / 2, self.contentSize.height / 2)];

            bonusPoints = [[DMConfig get].flawlessBonus intValue] * [[DMConfig get].level intValue];
            [DMConfig get].level = [NSNumber numberWithInt:[[DMConfig get].level intValue] + 1];
        } else if (blocksLeft < 8) {
            // Blocks left under minimum block limit -> level up.
            [DMConfig get].level = [NSNumber numberWithInt:[[DMConfig get].level intValue] + 1];
        } else {
            // Blocks left over minimum block limit -> game over.
            points = 0;
            endReason = DbEndReasonGameOver;
        }
        
        points += bonusPoints;
        [[DMConfig get] recordScore:[[DMConfig get].score unsignedIntValue] + points];
        [[DeblockAppDelegate get].hudLayer updateHudWithScore:bonusPoints];
        [[DeblockAppDelegate get].gameLayer stopGame:endReason];
    }

    locked = NO;
}


-(void) message:(NSString *)msg on:(CocosNode *)node {

    [self message:msg at:ccp(node.position.x, node.position.y + node.contentSize.height)];
}


-(void) message:(NSString *)msg at:(CGPoint)point {
    
    if(msgLabel)
        [msgLabel stopAllActions];
    
    else {
        msgLabel = [[Label alloc] initWithString:@""
                                      dimensions:CGSizeMake(1000, [[Config get].fontSize intValue] + 5)
                                       alignment:UITextAlignmentCenter
                                        fontName:[Config get].fixedFontName
                                        fontSize:[[Config get].fontSize intValue]];
        
        [self addChild:msgLabel z:9];
    }
    
    [msgLabel setString:msg];
    msgLabel.position = point;
    
    // Make sure label remains on screen.
    CGSize winSize = [Director sharedDirector].winSize;
    if([msgLabel position].x < [[Config get].fontSize intValue] / 2)                 // Left edge
        [msgLabel setPosition:ccp([[Config get].fontSize intValue] / 2, [msgLabel position].y)];
    if([msgLabel position].x > winSize.width - [[Config get].fontSize intValue] / 2) // Right edge
        [msgLabel setPosition:ccp(winSize.width - [[Config get].fontSize intValue] / 2, [msgLabel position].y)];
    if([msgLabel position].y < [[Config get].fontSize intValue] / 2)                 // Bottom edge
        [msgLabel setPosition:ccp([msgLabel position].x, [[Config get].fontSize intValue] / 2)];
    if([msgLabel position].y > winSize.width - [[Config get].fontSize intValue] * 2) // Top edge
        [msgLabel setPosition:ccp([msgLabel position].x, winSize.height - [[Config get].fontSize intValue] * 2)];
    
    // Color depending on whether message starts with -, + or neither.
    if([msg hasPrefix:@"+"])
        [msgLabel setRGB:0x66 :0xCC :0x66];
    else if([msg hasPrefix:@"-"])
        [msgLabel setRGB:0xCC :0x66 :0x66];
    else
        [msgLabel setRGB:0xFF :0xFF :0xFF];
    
    // Animate the label to fade out.
    [msgLabel runAction:[Spawn actions:
                         [FadeOut actionWithDuration:3],
                         [Sequence actions:
                          [DelayTime actionWithDuration:1],
                          [MoveBy actionWithDuration:2 position:ccp(0, [[Config get].fontSize intValue] * 2)],
                          nil],
                         nil]];
}


-(void) startGame {
    
    locked = NO;

    [[DeblockAppDelegate get].gameLayer started];
}


-(void) stopGame {
    
    locked = YES;

    BOOL isEmpty = YES;
    for (NSInteger row = 0; row < blockRows && isEmpty; ++row)
        for (NSInteger col = 0; col < blockColumns && isEmpty; ++col)
            if (blockGrid[row][col])
                isEmpty = NO;

    if (isEmpty)
        [[DeblockAppDelegate get].gameLayer stopped];
    else
        [self runAction:[Sequence actions:
                         [CallFunc actionWithTarget:self selector:@selector(blinkAll)],
                         [DelayTime actionWithDuration:0.5f],
                         [CallFunc actionWithTarget:self selector:@selector(destroyAll)],
                         [DelayTime actionWithDuration:0.5f],
                         [CallFunc actionWithTarget:[DeblockAppDelegate get].gameLayer selector:@selector(stopped)],
                         nil]];
}


- (void)blinkAll {

    for (NSInteger row = 0; row < blockRows; ++row)
        for (NSInteger col = 0; col < blockColumns; ++col)
            [[self blockAtRow:row col:col] blink];
}


- (void)destroyAll {
    
    for (NSInteger row = 0; row < blockRows; ++row)
        for (NSInteger col = 0; col < blockColumns; ++col)
            [self destroySingleBlockAtRow:row col:col];
}


-(void) dealloc {
    
    [msgLabel release];
    msgLabel = nil;
    
    [super dealloc];
}


@end
