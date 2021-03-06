{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}
module Day15 where

import Control.Lens
import Control.Monad
import Control.Monad.ST
import Data.Propagator
import Data.Propagator.Cell


-- boilerplate

link' :: Cell s a -> Prism' a b -> Cell s b -> ST s ()
link' outer prism inner = do
  watch outer $ \outerVal -> write' (outerVal ^? prism) inner
  watch inner $ \innerVal -> write outer (innerVal ^. re prism)

linkTy :: Cell s Term -> Cell s Term -> ST s ()
linkTy tmCell tyCell = do
  watch tmCell $ \tmVal -> write' (tmVal ^. tyL) tyCell
  watch tyCell $ \tyVal ->
    watch tmCell $ \tmVal -> write tmCell (tmVal & tyL .~ Just tyVal)

-- | Write only when the cell is not @Nothing@.
write' :: Maybe a -> Cell s a -> ST s ()
write' val cell = maybe (return ()) (write cell) val

withCell :: Propagated a => (Cell s a -> ST s ()) -> ST s (Cell s a)
withCell f = do
  x <- cell
  f x
  return x


-- orphans!

instance Propagated a => Propagated (Maybe a) where
  merge (Just a) (Just b) = Just <$> merge a b
  merge a@(Just _) Nothing = Change False a
  merge Nothing b@(Just _) = Change True b
  merge n _ = Change False n

instance Propagated String where


-- our terms

data Term
  = BVar { _bVarI :: Maybe Int, _ty :: Maybe Term }
  | FVar { _fVarS :: Maybe String, _ty :: Maybe Term }
  | Abs { _absTm :: Maybe Term, _ty :: Maybe Term }
  | App { _appTm1 :: Maybe Term, _appTm2 :: Maybe Term, _ty :: Maybe Term }
  | Type
  deriving Show

instance Propagated Term where
  merge (BVar i1 ty1) (BVar i2 ty2) =
    BVar <$> merge i1 i2 <*> merge ty1 ty2
  merge (FVar s1 ty1) (FVar s2 ty2) =
    FVar <$> merge s1 s2 <*> merge ty1 ty2
  merge (Abs t1 ty1) (Abs t2 ty2) =
    Abs <$> merge t1 t2 <*> merge ty1 ty2
  merge (App t11 t12 ty1) (App t21 t22 ty2) =
    App <$> merge t11 t21 <*> merge t12 t22 <*> merge ty1 ty2
  merge Type Type = Change False Type
  merge l r = Contradiction mempty ("term merge: " ++ show (l, r))


-- lenses / prisms
-- idea: we could make these all lenses by indexing Term...

tyL :: Lens' Term (Maybe Term)
tyL f tm = case tm of
  BVar i ty -> BVar i <$> f ty
  FVar s ty -> FVar s <$> f ty
  Abs subTm ty -> Abs subTm <$> f ty
  App t1 t2 ty -> App t1 t2 <$> f ty
  -- f :: Maybe Term -> f (Maybe Term)
  -- tm :: Term
  -- -> f Term
  Type -> (const Type) <$> f Nothing

tiP :: Prism' Term Int
tiP = prism' (flip BVar Nothing . Just) _bVarI

tsP :: Prism' Term String
tsP = prism' (flip FVar Nothing . Just) _fVarS

absP :: Prism' Term Term
absP = prism' (\tm -> Abs (Just tm) Nothing) (\(Abs tm _) -> tm)

t1P, t2P :: Prism' Term Term
t1P = prism' (\t1 -> App (Just t1) Nothing Nothing) (\(App t1 _ _) -> t1)
t2P = prism' (\t2 -> App Nothing (Just t2) Nothing) (\(App _ t2 _) -> t2)


-- links

mkBVar :: Cell s Int -> Cell s Term -> ST s (Cell s Term)
mkBVar iCell tyCell = withCell $ \c -> do
  link' c tiP iCell
  linkTy c tyCell

mkFVar :: Cell s String -> Cell s Term -> ST s (Cell s Term)
mkFVar sCell tyCell = withCell $ \c -> do
  link' c tsP sCell
  linkTy c tyCell

mkAbs :: Cell s Term -> Cell s Term -> ST s (Cell s Term)
mkAbs subTmCell tyCell = withCell $ \c -> do
  link' c absP subTmCell
  linkTy c tyCell

mkApp :: Cell s Term -> Cell s Term -> Cell s Term -> ST s (Cell s Term)
mkApp t1Cell t2Cell tyCell = withCell $ \c -> do
  link' c t1P t1Cell
  link' c t2P t2Cell
  linkTy c tyCell

mkType :: ST s (Cell s Term)
mkType = known Type


main :: IO ()
main = do
  print $ runST $ do
    a <- join $ mkFVar <$> known "a" <*> mkType
    a' <- join $ mkFVar <$> known "a" <*> mkType

    unify a a'

    (,) <$> content a <*> content a'

  print $ runST $ do
    [hole1, hole2] <- replicateM 2 cell
    a <- join $ mkFVar <$> known "a" <*> mkType
    b <- join $ mkFVar <$> known "b" <*> mkType
    c <- join $ mkFVar <$> known "c" <*> mkType

    x <- mkApp a hole1 c
    y <- mkApp hole2 b c

    unify x y
    (,) <$> content x <*> content y
