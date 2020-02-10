module Main exposing (Model, Msg(..), eview, initelts, main, update, view, viewCell)

import Array exposing (Array)
import Browser
import Browser.Dom as BD exposing (Element, getElement)
import Browser.Events as BE
import Browser.Navigation as BN
import Cellme exposing (..)
import Dict exposing (Dict)
import Element as E exposing (Element, centerX, column, el, fill, fillPortion, height, image, inFront, indexedTable, map, newTabLink, padding, paddingXY, paragraph, rgb, rgba, row, shrink, spacing, table, text, width)
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
    | RunButton


type alias Model =
    { elts : Array (Array Cell) }


initelts : Array (Array Cell)
initelts =
    Array.map
        (Array.map
            (\s ->
                { code = s
                , prog = Err ""
                , runstate = RsUnevaled
                }
            )
        )
    <|
        Array.fromList
            [ Array.fromList [ "1", "7", "8" ]
            , Array.fromList [ "2", "5", "6" ]
            , Array.fromList [ "9", "(+ (cv 1 0) (cv 1 1))", "0" ]
            ]


eview : Model -> Element Msg
eview model =
    let
        colf =
            \colidx ->
                let
                    ci =
                        colidx - 1
                in
                { header =
                    if colidx == 0 then
                        column [ Font.bold ]
                            [ text "x:"
                            , el [] <| text "y"
                            ]

                    else
                        text (String.fromInt ci)
                , width =
                    if colidx == 0 then
                        shrink

                    else
                        fill
                , view =
                    \rowidx array ->
                        if colidx == 0 then
                            text (String.fromInt rowidx)

                        else
                            Array.get ci array
                                |> Maybe.map
                                    (viewCell ci rowidx)
                                |> Maybe.withDefault (text "err")
                }

        rl =
            Array.get 0 model.elts
                |> Maybe.map Array.length
                |> Maybe.withDefault 0
    in
    column [ width fill, height fill, spacing 5, padding 5 ]
        [ newTabLink []
            { url = "https://github.com/bburdette/elm-sheet/"
            , label = el [ Font.color (rgb 0 0 0.6) ] <| text "elm-sheet on github"
            }
        , row [ spacing 5 ]
            [ EI.button
                [ BD.color (rgb 0.5 0.5 0.5)
                , Font.color (rgb 1 1 1)
                , Border.color (rgb 0 0 0.6)
                , paddingXY 5 3
                , Border.rounded 5
                ]
                { onPress = Just EvalButton
                , label = text "step"
                }
            , EI.button
                [ BD.color (rgb 0.5 0.5 0.5)
                , Font.color (rgb 1 1 1)
                , Border.color (rgb 0 0 0.6)
                , paddingXY 5 3
                , Border.rounded 5
                ]
                { onPress = Just RunButton
                , label = text "run"
                }
            ]
        , indexedTable
            [ width fill, height fill ]
            { data = Array.toList model.elts
            , columns =
                List.map colf (List.range 0 rl)
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
            case cell.runstate of
                RsOk term ->
                    text <| showTerm term

                RsErr s ->
                    el [ Font.color <| rgb 1 0.1 0.1 ] <| text <| "err: " ++ s

                RsUnevaled ->
                    text <| "unevaled"

                RsBlocked _ xib yib ->
                    text <| "blocked on cell (" ++ String.fromInt xib ++ ", " ++ String.fromInt yib ++ ")"
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
            ( { model
                | elts =
                    Array.get yi model.elts
                        |> Maybe.map
                            (\rowarray ->
                                Array.set yi (Array.set xi (defCell val) rowarray) model.elts
                            )
                        |> Maybe.withDefault model.elts
              }
            , Cmd.none
            )

        EvalButton ->
            ( { model | elts = evalCellsOnce model.elts }, Cmd.none )

        RunButton ->
            let
                ( cells, result ) =
                    evalCellsFully model.elts
            in
            ( { model | elts = cells }, Cmd.none )


main : Platform.Program () Model Msg
main =
    Browser.document
        { init = \() -> ( { elts = initelts }, Cmd.none )
        , subscriptions = \_ -> Sub.none
        , view = view
        , update = update
        }
