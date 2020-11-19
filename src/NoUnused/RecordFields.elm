module NoUnused.RecordFields exposing (rule)

{-|

@docs rule

-}

import Dict exposing (Dict)
import Elm.Syntax.Declaration as Declaration exposing (Declaration)
import Elm.Syntax.Exposing as Exposing
import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.Module as Module exposing (Module)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Range exposing (Range)
import Review.Rule as Rule exposing (Error, Rule)
import Set exposing (Set)


{-| Reports... REPLACEME

    config =
        [ NoUnused.RecordFields.rule
        ]


## Fail

    a =
        "REPLACEME example to replace"


## Success

    a =
        "REPLACEME example to replace"


## When (not) to enable this rule

This rule is useful when REPLACEME.
This rule is not useful when REPLACEME.


## Try it out

You can try this rule out by running the following command:

```bash
elm-review --template jfmengels/elm-review-unused/example --rules NoUnused.RecordFields
```

-}
rule : Rule
rule =
    Rule.newModuleRuleSchema "NoUnused.RecordFields" initialContext
        |> Rule.withModuleDefinitionVisitor moduleDefinitionVisitor
        |> Rule.withDeclarationListVisitor declarationListVisitor
        |> Rule.withExpressionEnterVisitor expressionVisitor
        |> Rule.withFinalModuleEvaluation finalEvaluation
        |> Rule.fromModuleRuleSchema


type alias Context =
    { variables : Dict String Variable
    , expressionsToIgnore : Set String
    , exposes : Exposes
    }


type alias Variable =
    { usedFields : Set String
    , declaredFields : List (Node String)
    , wasUsedWithoutFieldAccess : Bool
    }


initialContext : Context
initialContext =
    { variables = Dict.empty
    , expressionsToIgnore = Set.empty
    , exposes = ExposesEverything
    }


type Exposes
    = ExposesEverything
    | ExposesExplicitly (Set String)


moduleDefinitionVisitor : Node Module -> Context -> ( List nothing, Context )
moduleDefinitionVisitor moduleNode moduleContext =
    case Module.exposingList (Node.value moduleNode) of
        Exposing.All _ ->
            ( [], { moduleContext | exposes = ExposesEverything } )

        Exposing.Explicit list ->
            let
                names : List String
                names =
                    List.map
                        (\(Node _ node) ->
                            case node of
                                Exposing.FunctionExpose name ->
                                    name

                                Exposing.TypeOrAliasExpose name ->
                                    name

                                Exposing.TypeExpose { name } ->
                                    name

                                Exposing.InfixExpose name ->
                                    name
                        )
                        list
            in
            ( [], { moduleContext | exposes = ExposesExplicitly (Set.fromList names) } )


declarationListVisitor : List (Node Declaration) -> Context -> ( List nothing, Context )
declarationListVisitor nodes context =
    let
        variables : Dict String Variable
        variables =
            nodes
                |> List.filterMap (registerDeclaration context.exposes)
                |> Dict.fromList
    in
    ( [], { context | variables = Dict.union variables context.variables } )


registerDeclaration : Exposes -> Node Declaration -> Maybe ( String, Variable )
registerDeclaration exposes node =
    case Node.value node of
        Declaration.FunctionDeclaration function ->
            let
                declaration =
                    Node.value function.declaration

                name =
                    Node.value declaration.name
            in
            case exposes of
                ExposesEverything ->
                    Nothing

                ExposesExplicitly exposedNames ->
                    if not (Set.member name exposedNames) && List.isEmpty declaration.arguments then
                        case Node.value function.declaration |> .expression |> Node.value of
                            Expression.RecordExpr fields ->
                                let
                                    declaredFields : List (Node String)
                                    declaredFields =
                                        List.map (Node.value >> Tuple.first) fields
                                in
                                Just
                                    ( name
                                    , { usedFields = Set.empty
                                      , declaredFields = declaredFields
                                      , wasUsedWithoutFieldAccess = False
                                      }
                                    )

                            _ ->
                                Nothing

                    else
                        Nothing

        _ ->
            Nothing


expressionVisitor : Node Expression -> Context -> ( List nothing, Context )
expressionVisitor node context =
    case Node.value node of
        Expression.RecordAccess (Node functionOrValueRange (Expression.FunctionOrValue [] name)) fieldName ->
            let
                variables : Dict String Variable
                variables =
                    Dict.update name
                        (\maybeDeclared ->
                            case maybeDeclared of
                                Just declared ->
                                    Just { declared | usedFields = Set.insert (Node.value fieldName) declared.usedFields }

                                Nothing ->
                                    Nothing
                        )
                        context.variables
            in
            ( []
            , { context
                | variables = Dict.union variables context.variables
                , expressionsToIgnore = Set.insert (stringifyRange functionOrValueRange) context.expressionsToIgnore
              }
            )

        Expression.FunctionOrValue [] name ->
            if Set.member (stringifyRange (Node.range node)) context.expressionsToIgnore then
                ( [], context )

            else
                let
                    variables : Dict String Variable
                    variables =
                        Dict.update name
                            (\maybeDeclared ->
                                case maybeDeclared of
                                    Just declared ->
                                        Just { declared | wasUsedWithoutFieldAccess = True }

                                    Nothing ->
                                        Nothing
                            )
                            context.variables
                in
                ( []
                , { context | variables = Dict.union variables context.variables }
                )

        _ ->
            ( [], context )


stringifyRange : Range -> String
stringifyRange range =
    [ range.start.row
    , range.start.column
    , range.end.row
    , range.end.column
    ]
        |> List.map String.fromInt
        |> String.join "-"


finalEvaluation : Context -> List (Error {})
finalEvaluation context =
    context.variables
        |> Dict.toList
        |> List.concatMap (Tuple.second >> finalEvaluationForVariable)


finalEvaluationForVariable : Variable -> List (Error {})
finalEvaluationForVariable variable =
    if variable.wasUsedWithoutFieldAccess then
        []

    else
        variable.declaredFields
            |> List.filter (\node -> not <| Set.member (Node.value node) variable.usedFields)
            |> List.map
                (\node ->
                    Rule.error
                        { message = "Unused field `" ++ Node.value node ++ "`"
                        , details = [ "REPLACEME" ]
                        }
                        (Node.range node)
                )
