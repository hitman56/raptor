-- Copyright 2013 Dat Le <dat.le@zalora.com>

module Main where 
import Data.List.Split
import Data.List
import Data.Char
import System.IO
import System.Environment
import Text.Printf
import Data.Ord
import qualified Data.Map as Map

type DataFrame = [[String]]
type Row = [String]
type SKU = String
type SKU_Distance = String
type USER = String
main = do
		args <- getArgs
		let country = args !! 0 
		let size = read $ args !! 1
		let algorithm = args !! 2
		purchase <- readFile $ "Data/VTD_purchased_" ++ country ++ ".csv"
		view 	 <- readFile $ "Data/VTD_view_" ++ country ++ ".csv"
		cart 	 <- readFile $ "Data/VTD_cart_" ++ country ++ ".csv"
		valid    <- readFile $ "Data/valid_skus_" ++ country ++ ".csv"
		instock  <- readFile $ "Data/instock_skus_" ++ country ++ ".csv"
		male     <- readFile $ "Data/sku_male_" ++ country ++ ".csv"
		female   <- readFile $ "Data/sku_female_" ++ country ++ ".csv"
		let sku_src = indexAsList instock
		let sku_dst = indexAsList valid
		let sku_male = indexAsList male
		let sku_female = indexAsList female
		let sku_dst_male = intersect sku_male sku_dst
		let sku_dst_female = intersect sku_female sku_dst
		let sku_src_male = intersect sku_male sku_src
		let sku_src_female = intersect sku_female sku_src
		let purchase_map = toMap purchase
		let view_map = toMap view
		let cart_map = toMap cart
		outh <- openFile ("Result/" ++ algorithm ++ "/Raptor_" ++ country ++ ".csv") WriteMode
		case algorithm of
			"original" -> hPutStrLn outh (toStr country (apply_jaccard size sku_src_male sku_dst_male purchase_map cart_map)) >>
			              hPutStrLn outh (toStr country (apply_jaccard size sku_src_female sku_dst_female purchase_map cart_map)) >>
			              hClose outh
			"bayes" -> hPutStrLn outh (toStr country (apply_bayes_jaccard size sku_src_male sku_dst_male purchase_map view_map)) >>
			           hPutStrLn outh (toStr country (apply_bayes_jaccard size sku_src_female sku_dst_female purchase_map view_map)) >>
			           hClose outh
			"vtd" -> hPutStrLn outh (toStr country (apply_vtd_jaccard size sku_src_male sku_dst_male purchase_map view_map)) >>
			         hPutStrLn outh (toStr country (apply_vtd_jaccard size sku_src_female sku_dst_female purchase_map view_map)) >>
					 hClose outh

-- original
apply_jaccard :: Int -> [SKU] -> [SKU] -> (Map.Map SKU [USER]) -> (Map.Map SKU [USER]) -> [(SKU,[(SKU,Float)])]
apply_jaccard size sku_src sku_dst purchase_map cart_map = 
	[ (sku1, apply_jaccard_for_sku size sku1 sku_src sku_dst purchase_map cart_map) | sku1 <- sku_src ]

apply_jaccard_for_sku :: Int -> SKU -> [SKU] -> [SKU] -> (Map.Map SKU [USER]) -> (Map.Map SKU [USER]) -> [(SKU,Float)]
apply_jaccard_for_sku size sku1 sku_src sku_dst purchase_map cart_map = 
	take size $ sortBy (flip (comparing snd)) $ 
	[ (sku2,(jaccard sku1 sku2 purchase_map cart_map)) | sku2 <- filter_related_sku sku1 sku_dst cart_map]

jaccard :: SKU -> SKU -> (Map.Map SKU [USER]) -> (Map.Map SKU [USER]) -> Float
jaccard sku1 sku2 purchase_map cart_map = 
	let purchase_sku1 = safeVal purchase_map sku1 in
	let purchase_sku2 = safeVal purchase_map sku2 in
	let ints_purchase = floatLen (intersect purchase_sku1 purchase_sku2) in
	let cart_sku1 = safeVal cart_map sku1 in
	let cart_sku2 = safeVal cart_map sku2 in
	let ints_cart = floatLen (intersect cart_sku1 cart_sku2) in
	(wilson95 ints_purchase (floatLen purchase_sku1 + floatLen purchase_sku2 - ints_purchase)) 
	+ 0.2 * (wilson95 ints_cart (floatLen cart_sku1 + floatLen cart_sku2 - ints_cart)) 

-- bayes
apply_bayes_jaccard :: Int -> [SKU] -> [SKU] -> (Map.Map SKU [USER]) -> (Map.Map SKU [USER]) -> [(SKU,[(SKU,Float)])]
apply_bayes_jaccard size sku_src sku_dst purchase_map view_map  = 
	[ (sku1, apply_bayes_jaccard_for_sku size sku1 sku_src sku_dst purchase_map view_map ) | sku1 <- sku_src]

apply_bayes_jaccard_for_sku :: Int -> SKU -> [SKU] -> [SKU] -> (Map.Map SKU [USER]) -> (Map.Map SKU [USER]) -> [(SKU,Float)]
apply_bayes_jaccard_for_sku size sku1 sku_src sku_dst purchase_map view_map = 
	take size $ sortBy (flip (comparing snd)) $ 
	[ (sku2,(bayes_jaccard sku1 sku2 purchase_map view_map )) | sku2 <- filter_related_sku sku1 sku_dst purchase_map ]

bayes_jaccard :: SKU -> SKU -> (Map.Map SKU [USER]) -> (Map.Map SKU [USER]) -> Float
bayes_jaccard sku1 sku2 purchase_map view_map 
	| floatLen (intersect (safeVal purchase_map sku1) (safeVal purchase_map sku2)) == 0 = 0 
	| otherwise = let purchase_sku1 = safeVal purchase_map sku1 in
				  let purchase_sku2 = safeVal purchase_map sku2 in
				  let view_sku1     = safeVal view_map sku1 in
				  let view_sku2     = safeVal view_map sku2 in
				  let ints_view     = floatLen (intersect view_sku1 view_sku2) in
				  let ints_purchase = floatLen (intersect purchase_sku1 purchase_sku2) in
				  let ints_purchase1_view2 = floatLen (intersect purchase_sku1 view_sku2) in
				  let ints_purchase2_view1 = floatLen (intersect purchase_sku2 view_sku1) in
				  wilson95 ints_purchase (ints_purchase1_view2 + ints_purchase2_view1)

-- vtd
apply_vtd_jaccard :: Int -> [SKU] -> [SKU] -> (Map.Map SKU [USER]) -> (Map.Map SKU [USER]) -> [(SKU,[(SKU,Float)])]
apply_vtd_jaccard size sku_src sku_dst purchase_map view_map  = 
	[ (sku1, apply_vtd_jaccard_for_sku size sku1 sku_src sku_dst purchase_map view_map ) | sku1 <- sku_src]

apply_vtd_jaccard_for_sku :: Int -> SKU -> [SKU] -> [SKU] -> (Map.Map SKU [USER]) -> (Map.Map SKU [USER]) -> [(SKU,Float)]
apply_vtd_jaccard_for_sku size sku1 sku_src sku_dst purchase_map view_map = 
	take size $ sortBy (flip (comparing snd)) $ 
	[ (sku2,(vtd_jaccard sku1 sku2 purchase_map view_map )) | sku2 <- filter_related_sku_vtd sku1 sku_dst purchase_map view_map ]

vtd_jaccard :: SKU -> SKU -> (Map.Map SKU [USER]) -> (Map.Map SKU [USER]) -> Float
vtd_jaccard sku1 sku2 purchase_map view_map = let view_sku1 	  = safeVal view_map sku1 in
												let view_sku2 	  = safeVal view_map sku2 in
												let purchase_sku2 = safeVal purchase_map sku2 in
				 							    let ints_purchase2_view1 = floatLen (intersect purchase_sku2 view_sku1) in
				 							    let ints_view            = floatLen (intersect view_sku1 view_sku2) in
				 							    wilson95 ints_purchase2_view1 ints_view

-- auxilary functions
-- given an SKU, a list of SKUs to be fitered, a purchase_map
-- output list of SKUs that has at least one or more purchases together with the given SKU
filter_related_sku :: SKU -> [SKU] -> (Map.Map SKU [USER]) ->[SKU]
filter_related_sku sku sku_dst purchase_map = 
	filter (\other_sku -> other_sku /= sku && 
					       length (intersect (safeVal purchase_map other_sku) (safeVal purchase_map sku)) > 0) sku_dst

filter_related_sku_vtd :: SKU -> [SKU] -> (Map.Map SKU [USER]) -> (Map.Map SKU [USER]) ->[SKU]
filter_related_sku_vtd sku sku_dst purchase_map view_map = 
	filter (\other_sku -> other_sku /= sku && 
					       length (intersect (safeVal purchase_map other_sku) (safeVal view_map sku)) > 0) sku_dst

floatLen :: [String] -> Float
floatLen s =  fromIntegral $ length $ s

safeVal :: Ord a => (Map.Map a [a]) -> a -> [a]
safeVal map key | Map.member key map = map Map.! key
                | otherwise = []

toMap :: String -> Map.Map SKU [USER]
toMap input = Map.fromList $ map (\row -> (row !! 0, splitOn " " (row !!1))) $ toDataFrame "\t" input

indexAsList :: String -> [String]
indexAsList input = tail $ map (\row -> row !! 0) $ toDataFrame "\t" input

toDataFrame :: String -> String -> DataFrame
toDataFrame input sep = map (splitOn sep) (lines input)

toStr :: String ->  [(SKU,[(SKU,Float)])] -> String
toStr country result = intercalate "\n" $ map (\(sku,skus) -> country ++ "\t" ++ sku ++ "\t" ++ intercalate "\t" (map (\(sku,score) -> (printf "%.2f" score :: String) ++ "-" ++ sku) skus)) result 

wilson95 :: Float -> Float -> Float
wilson95 0 0 = 0
wilson95 positive negative = 100 * ((positive + 1.9208) / (positive + negative) - 1.96 * sqrt((positive * negative) / (positive + negative) + 0.9604) / (positive + negative)) /  (1 + 3.8416 / (positive + negative))
