-- | all operations have fixed bit length,
-- and are unsatisfiable in case of overflows.

module Satchmo.Integer.Op 

( negate, add, sub, times
, gt, ge, eq 
)

where

import Satchmo.Integer.Data
import Prelude hiding ( and, or, not, negate )
import Satchmo.Boolean hiding ( constant )
import qualified  Satchmo.Boolean as B

import qualified Satchmo.Binary.Op.Common as C
import qualified Satchmo.Binary.Op.Flexible as F
import qualified Satchmo.Binary.Op.Times as T

import Control.Monad ( forM, when )

-- | negate. Unsatisfiable if value is lowest negatve.
negate :: MonadSAT m 
       => Number -> m Number
negate n = do
    let ys = map B.not $ bits n 
    o <- B.constant True
    ( zs, c ) <- increment ys o
    assertOr [ last $ ys, B.not $ last zs ]
    return $ make zs

increment [] z = return ( [], z )
increment (y:ys) z = do
    ( r, d ) <- C.half_adder y z
    ( rs, c ) <- increment ys d
    return ( r : rs, c )

add :: MonadSAT m 
    => Number -> Number 
    -> m Number
add a0 b0 = do

    let w = max (width a0) (width b0)
        a = sextn w a0 ; b = sextn w b0

    cin <- B.constant False
    ( zs, cout ) <- 
        F.add_with_carry cin ( bits a ) ( bits b )
    let c = make zs
    sab <- B.fun2 (==) (sign a) (sign b)
    sac <- B.fun2 (==) (sign a) (sign c)
    B.assert [ B.not sab , sac ]
    return c

sub :: MonadSAT m 
    => Number -> Number 
    -> m Number
sub a b = do
    when ( width a /= width b ) 
    	 $ error "Satchmo.Integer.Op.sub"
    c <- negate b
    add a c

sextn w n = make $ sext n w

times :: MonadSAT m 
    => Number -> Number 
    -> m Number
times a0 b0 = do

    let w = max (width a0) (width b0)
        a = sextn w a0 ; b = sextn w b0
        
    cs <- T.times' T.Ignore (Just w) (bits a) (bits b)

    nza <- or $ bits a ; nzb <- or $ bits b
    result_should_be_nonzero <- and [ nza, nzb ]
    result_is_nonzero <- or cs

    assert [ not result_should_be_nonzero, result_is_nonzero ]

    xs <- forM (bits a) $ \ x -> fun2 (/=) x (sign a)
    ys <- forM (bits b) $ \ y -> fun2 (/=) y (sign b)
    
    forM (zip [0..w-2] xs) $ \ (i,x) ->
      forM (zip [0..w-2] ys) $ \ (j,y) ->
        when (i+j>=w-1) $ assert [ not x, not y ]

    let c = make cs

    s <- fun2 (/=) (sign a) (sign b)
    ok <- fun2 (==) s (sign c)
    
    assert [ not result_is_nonzero, ok ]
    
    return c

-- | inefficient (used double-bit width computation)
times_model :: MonadSAT m 
    => Number -> Number 
    -> m Number
times_model a b = do
    when ( width a /= width b ) 
    	 $ error "Satchmo.Integer.Op.times"
    let w = width a
    cs <- T.times' T.Ignore (Just (2*w)) (sext a w) (sext b w)
    let (small, large) = splitAt w cs
    allone <- B.and large ; allzero <- B.and ( map B.not large )
    B.assert [ allone, allzero ]
    e <- B.fun2 (==) (last small) (head large)
    B.assert[e]
    return $ make small

sext a w = bits a ++ replicate (w - width a) (sign a)
    

----------------------------------------------------

positive :: MonadSAT m
	 => Number 
	 -> m Boolean
positive n = do
    ok <- or $ init $ bits n   
    and [ ok, not $ last $ bits n ]

negative :: MonadSAT m
	 => Number 
	 -> m Boolean
negative n = do
    return $ last $ bits n

nonnegative :: MonadSAT m
	 => Number 
	 -> m Boolean
nonnegative n = do
    return $ not $ last $ bits n

----------------------------------------------------

eq :: MonadSAT m 
   => Number -> Number
   -> m Boolean
eq a b = do
    when ( width a /= width b ) 
    	 $ error "Satchmo.Integer.Op.eq"
    eqs <- forM ( zip ( bits a ) ( bits b ) )
    	   $ \ (x,y) -> fun2 (==) x y
    and eqs

gt :: MonadSAT m 
   => Number -> Number
   -> m Boolean
gt a b = do
    diff <- and [ not $ last $ bits a, last $ bits b ]
    same <- fun2 (==) ( last $ bits a )	
     	     	       ( last $ bits b )
    g <- F.gt ( F.make $ bits a ) 
      	      ( F.make $ bits b )
    monadic or [ return diff
    	       , and [ same, g ]
	       ]

ge :: MonadSAT m 
   => Number -> Number
   -> m Boolean
ge a b = do
    diff <- and [ not $ last $ bits a, last $ bits b ]
    same <- fun2 (==) ( last $ bits a )	
     	     	       ( last $ bits b )
    g <- F.ge ( F.make $ bits a ) 
      	      ( F.make $ bits b )
    monadic or [ return diff
    	       , and [ same, g ]
	       ]
    
