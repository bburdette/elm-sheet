module Main exposing (Model, Msg(..), eview, initelts, main, update, view, viewCell)

import Array exposing (Array)
import Browser
import Browser.Dom as BD exposing (Element, getElement)
import Browser.Events as BE
import Browser.Navigation as BN
import Cellme exposing (..)
import Dict exposing (Dict)
import Element as E exposing (Element, centerX, column, el, fill, fillPortion, height, image, inFront, indexedTable, map, newTabLink, paddingXY, paragraph, rgb, rgba, row, shrink, spacing, table, text, width)
import Element.Background as BD
import Element.Border as Border
import Element.Events as EE
import Element.Font as Font
import Element.Input as EI
import EvalStep exposing (NameSpace, Term(..))
import Prelude exposing (BuiltInFn)
import Run exposing (compile, runCount)
import Show exposing (showTerm, showTerms)
import Toop as T


type Msg
    = Noop
    | CellVal Int Int String
    | EvalButton


type alias Model =
    { elts : Array (Array Cell) }


initelts =
    Array.map
        (Array.map
            (\s ->
                { code = s
                , prog = Err ""
                , runstate = RsErr ""
                }
            )
        )
    <|
        Array.fromList
            [ Array.fromList [ "1", "7", "8" ]
            , Array.fromList [ "2", "5", "6" ]
            , Array.fromList [ "9", "(cv 1 0)", "0" ]
            ]


eview : Model -> Element Msg
eview model =
    let
        colf =
            \colidx ->
                { header = text (String.fromInt colidx)
                , width = fill
                , view =
                    \rowidx array ->
                        Array.get colidx array
                            |> Maybe.map
                                (viewCell colidx rowidx)
                            |> Maybe.withDefault (text "err")
                }
    in
    column [ width fill, height fill ]
        [ EI.button
            [ BD.color (rgb 0 0.1 0.7)
            , Font.color (rgb 1 1 1)
            , Border.color (rgb 0 0 0.6)
            , paddingXY 5 3
            , Border.rounded 5
            ]
            { onPress = Just EvalButton
            , label = text "eval"
            }
        , indexedTable
            [ width fill, height fill ]
            { data = Array.toList model.elts
            , columns =
                List.map colf (List.range 0 (Array.length model.elts - 1))
            }
        ]


viewCell : Int -> Int -> Cell -> Element Msg
viewCell xi yi cell =
    column [ width fill ]
        [ EI.text [ width fill ]
            { onChange = \v -> CellVal xi yi v
            , text = cell.code
            , placeholder = Nothing
            , label = EI.labelHidden ("cell" ++ String.fromInt xi ++ "," ++ String.fromInt yi)
            }
        , el [ width fill ] <|
            E.text
                (case cell.runstate of
                    RsOk term ->
                        showTerm term

                    RsErr s ->
                        "err: " ++ s

                    RsBlocked _ xib yib ->
                        "blocked on cell (" ++ String.fromInt xib ++ ", " ++ String.fromInt yib ++ ")"
                )
        ]


view : Model -> Browser.Document Msg
view model =
    { title = "schelmesheet"
    , body =
        [ E.layout [] <| eview model
        ]
    }


defCell : String -> Cell
defCell s =
    { code = s, prog = Err "", runstate = RsErr "" }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Noop ->
            ( model, Cmd.none )

        CellVal xi yi val ->
            let
                _ =
                    Debug.log "CellVal" ( xi, yi, val )
            in
            ( { model
                | elts =
                    Array.get yi model.elts
                        |> Maybe.map
                            (\rowarray ->
                                Debug.log "elts:" <|
                                    Array.set yi (Array.set xi (defCell val) rowarray) model.elts
                            )
                        |> Maybe.withDefault model.elts
              }
            , Cmd.none
            )

        EvalButton ->
            ( { model | elts = evalCells model.elts }, Cmd.none )


main =
    Browser.document
        { init = \() -> ( { elts = initelts }, Cmd.none )
        , subscriptions = \_ -> Sub.none
        , view = view
        , update = update
        }
