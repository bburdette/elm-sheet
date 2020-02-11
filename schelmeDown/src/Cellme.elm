module Cellme exposing (Cell, CellContainer(..), CellState(..), CellStatus(..), FullEvalResult(..), PRes(..), PSideEffectorFn, RunState(..), cellVal, cellme, compileCells, compileError, continueCell, evalArgsPSideEffector, evalCell, evalCellsFully, evalCellsOnce, isLoopedCell, loopCheck, maybeIsJust, runCell, runCellBody)

import Dict exposing (Dict)
import Eval exposing (evalBody, evalTerm, evalTerms)
import EvalStep exposing (EvalBodyStep(..), EvalTermsStep(..), NameSpace, SideEffector, SideEffectorStep(..), Term(..))
import Prelude exposing (BuiltInFn)
import Run exposing (compile, runCount)
import Show exposing (showTerm, showTerms)
import StateGet exposing (getEvalBodyStepState)
import StateSet exposing (setEvalBodyStepState)


{-| the state that is used during cell eval.
-}
type CellContainer id cc
    = CellContainer
        { getCell : id -> CellContainer id cc -> Maybe (Cell id (CellState id cc))
        , setCell : id -> Cell id (CellState id cc) -> CellContainer id cc -> Result String (CellContainer id cc)
        , map : (Cell id (CellState id cc) -> Cell id (CellState id cc)) -> CellContainer id cc -> CellContainer id cc
        , has : (Cell id (CellState id cc) -> Bool) -> CellContainer id cc -> Bool
        , makeId : List (Term (CellState id cc)) -> Result String id
        , showId : id -> String
        , cells : cc

        -- , setCell : id -> Cell id cc -> Result String (CellContainer id)
        }



-- type alias CellArray =
--     { cells : Array (Array Int)
--     , getCell : ( Int, Int ) -> CellContainer CellArray -> Maybe (Cell ( Int, Int ))
--     , map : (Cell ( Int, Int ) -> Cell ( Int, Int )) -> CellContainer CellArray -> CellContainer CellArray
--     , has : (Cell ( Int, Int ) -> Bool) -> CellContainer CellArray -> Bool
--     }
-- , cells = Array (Array (Cell ( Int, Int )))
-- (Int, Int) ->  Array (Array Cell) -> Int -> Int -> Maybe Cell
-- getCell icells xi yi =


type CellState id cc
    = CellState
        { cells : CellContainer id cc
        , cellstatus : CellStatus id
        }


type alias Cell id cs =
    { code : String
    , prog : Result String (List (Term cs))
    , runstate : RunState id cs
    }


type CellStatus id
    = AllGood
    | Blocked id


type RunState id cs
    = RsBlocked (EvalBodyStep cs) id
    | RsErr String
    | RsUnevaled
    | RsOk (Term cs)


{-| the cell language is schelme plus 'cv'
-}
cellme : NameSpace (CellState id cc)
cellme =
    Prelude.prelude
        |> Dict.union Prelude.math
        |> Dict.insert "cv"
            (TSideEffector (evalArgsPSideEffector cellVal))


compileCells : CellContainer id cc -> CellContainer id cc
compileCells cells =
    let
        (CellContainer cellc) =
            cells

        compileCell =
            \cell -> { cell | prog = Run.compile cell.code }
    in
    cellc.map compileCell cells


clearCells : CellContainer id cc -> CellContainer id cc
clearCells cells =
    let
        (CellContainer cellc) =
            cells

        clearCell =
            \cell -> { cell | runstate = RsUnevaled }
    in
    cellc.map clearCell cells


{-| run cell from the start.
-}
runCell : CellContainer id cc -> Cell id (CellState id cc) -> Cell id (CellState id cc)
runCell cells cell =
    case cell.prog of
        Err _ ->
            cell

        Ok p ->
            { cell
                | runstate =
                    runCellBody (EbStart cellme (CellState { cells = cells, cellstatus = AllGood }) p)
            }


{-| continue running the cell.
-}
continueCell : CellContainer id cc -> Cell id (CellState id cc) -> Cell id (CellState id cc)
continueCell cells cell =
    case cell.prog of
        Err _ ->
            cell

        Ok _ ->
            case cell.runstate of
                RsBlocked cb _ ->
                    { cell
                        | runstate = runCellBody (setEvalBodyStepState cb (CellState { cells = cells, cellstatus = AllGood }))
                    }

                _ ->
                    cell


type FullEvalResult
    = FeOk
    | FeLoop
    | FeEvalError
    | FeCompileError


compileError : CellContainer id cc -> Bool
compileError (CellContainer cells) =
    cells.has
        (\cell ->
            case cell.prog of
                Err _ ->
                    True

                _ ->
                    False
        )
        (CellContainer cells)


isLoopedCell : CellContainer id cc -> List id -> Cell id (CellState id cc) -> Maybe (List id)
isLoopedCell cellc loop cell =
    let
        (CellContainer cells) =
            cellc
    in
    case cell.runstate of
        RsBlocked _ id ->
            if List.member id loop then
                Just loop

            else
                cells.getCell id cellc |> Maybe.andThen (isLoopedCell cellc (id :: loop))

        RsUnevaled ->
            Nothing

        RsErr _ ->
            Nothing

        RsOk _ ->
            Nothing


maybeIsJust : Maybe a -> Bool
maybeIsJust mba =
    case mba of
        Just _ ->
            True

        Nothing ->
            False


errorCheck : CellContainer id cc -> Bool
errorCheck cellc =
    let
        (CellContainer cells) =
            cellc
    in
    cells.has
        (\cell ->
            case cell.runstate of
                RsErr _ ->
                    True

                _ ->
                    False
        )
        cellc


loopCheck : CellContainer id cc -> Bool
loopCheck cellc =
    let
        (CellContainer cells) =
            cellc
    in
    cells.has (\cell -> isLoopedCell cellc [] cell |> maybeIsJust) cellc


{-| should eval all cells, resulting in an updated array and result type.
-}
evalCellsFully : CellContainer id cc -> ( CellContainer id cc, FullEvalResult )
evalCellsFully (CellContainer initcells) =
    let
        compiledCells =
            CellContainer initcells
                |> compileCells
                |> clearCells
    in
    if compileError compiledCells then
        ( compiledCells, FeCompileError )

    else
        compiledCells
            |> initcells.map (runCell compiledCells)
            |> runCellsFully


runCellsFully : CellContainer id cc -> ( CellContainer id cc, FullEvalResult )
runCellsFully cellc =
    let
        (CellContainer cells) =
            cellc
    in
    if loopCheck cellc then
        ( cellc, FeLoop )

    else if errorCheck cellc then
        ( cellc, FeEvalError )

    else if
        cells.has
            (\cell ->
                case cell.runstate of
                    RsBlocked _ _ ->
                        True

                    RsUnevaled ->
                        False

                    RsErr _ ->
                        False

                    RsOk _ ->
                        False
            )
            cellc
    then
        runCellsFully (cells.map (continueCell cellc) cellc)

    else
        ( cellc, FeOk )


evalCell : CellContainer id cc -> Cell id (CellState id cc) -> Cell id (CellState id cc)
evalCell cells cell =
    let
        prog =
            Run.compile cell.code
    in
    case prog of
        Err _ ->
            { cell | prog = prog }

        Ok p ->
            { cell
                | runstate =
                    runCellBody (EbStart cellme (CellState { cells = cells, cellstatus = AllGood }) p)
            }


{-| should eval all cells, resulting in an updated array.
-}
evalCellsOnce : CellContainer id cc -> CellContainer id cc
evalCellsOnce (CellContainer initcells) =
    let
        unevaledCells =
            CellContainer initcells
    in
    initcells.map (evalCell unevaledCells) unevaledCells


type PRes id cc
    = PrOk ( NameSpace (CellState id cc), CellState id cc, Term (CellState id cc) )
    | PrPause (CellState id cc)
    | PrErr String


{-| function type to pass to evalArgsSideEffector
-}
type alias PSideEffectorFn id cc =
    NameSpace (CellState id cc) -> CellState id cc -> List (Term (CellState id cc)) -> PRes id cc


runCellBody : EvalBodyStep (CellState id cc) -> RunState id (CellState id cc)
runCellBody ebs =
    case ebs of
        EbError e ->
            RsErr e

        EbFinal _ _ term ->
            RsOk term

        _ ->
            case getEvalBodyStepState ebs of
                Just (CellState s) ->
                    case s.cellstatus of
                        AllGood ->
                            runCellBody (evalBody ebs)

                        Blocked id ->
                            RsBlocked ebs id

                Nothing ->
                    RsErr "error - no step state"


{-| just like the regular evalArgsSideEffector, except checks for PrPause from the fn.
-}
evalArgsPSideEffector : PSideEffectorFn id cc -> SideEffector (CellState id cc)
evalArgsPSideEffector fn =
    \step ->
        case step of
            SideEffectorStart ns state terms ->
                SideEffectorArgs ns state (evalTerms (EtStart ns state terms))

            SideEffectorArgs ns state ets ->
                case ets of
                    EtFinal efns enstate terms ->
                        -- we have all args, now call our 'built in'
                        case fn ns enstate terms of
                            PrOk ( nebins, nestate, term ) ->
                                SideEffectorFinal nebins nestate term

                            PrErr e ->
                                SideEffectorError e

                            PrPause pstate ->
                                -- result in the same step we are in now, except with updated state.
                                -- caller will need to check for blockage there.
                                SideEffectorArgs ns pstate (EtFinal efns pstate terms)

                    EtError e ->
                        SideEffectorError e

                    _ ->
                        SideEffectorArgs ns state (evalTerms ets)

            SideEffectorEval _ _ _ _ ->
                SideEffectorError "not expecting SideEffectorEval!"

            SideEffectorBody _ _ _ _ ->
                SideEffectorError "unexpected SideEffectorBody"

            SideEffectorFinal _ _ _ ->
                step

            SideEffectorError _ ->
                step


cellVal : PSideEffectorFn id cc
cellVal ns (CellState state) args =
    let
        (CellContainer cellc) =
            state.cells
    in
    case cellc.makeId args of
        Ok id ->
            cellc.getCell id state.cells
                |> Maybe.map
                    (\cell ->
                        case cell.runstate of
                            RsBlocked _ _ ->
                                PrPause <| CellState { state | cellstatus = Blocked id }

                            RsErr _ ->
                                PrErr <| "Blocked on error in : " ++ cellc.showId id

                            RsUnevaled ->
                                PrPause <| CellState { state | cellstatus = Blocked id }

                            RsOk val ->
                                PrOk ( ns, CellState { state | cellstatus = AllGood }, val )
                    )
                |> Maybe.withDefault (PrErr <| "cell not found: " ++ cellc.showId id)

        Err e ->
            PrErr e
