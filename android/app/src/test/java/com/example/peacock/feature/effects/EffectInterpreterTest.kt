package com.example.peacock.feature.effects

import com.example.peacock.feature.runtime.GroupState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Test

class EffectInterpreterTest {
    @Test
    fun infiniteHueAdjustmentAccumulatesAcrossCycles() {
        val compiled = compiled(
            EffectOp.Repeat(
                count = null,
                body = listOf(
                    EffectOp.AdjustHsv(EffectTarget.ALL, dh = 6, ds = 0, dv = 0),
                    EffectOp.Wait(100),
                ),
            ),
        )
        val interpreter = EffectInterpreter(compiled, groups(hue = 0, mode = 4))

        assertEquals(6, interpreter.frameAt(0).groups.first().hue)
        assertEquals(6, interpreter.frameAt(99).groups.first().hue)
        assertEquals(12, interpreter.frameAt(100).groups.first().hue)
        assertEquals(66, interpreter.frameAt(1_000).groups.first().hue)
        assertEquals(1, interpreter.frameAt(1_000).groups.first().innerMode)
        assertFalse(interpreter.frameAt(10_000).finished)
    }

    @Test
    fun finiteProgramAppliesInitialColorImmediatelyAndSendsExactFinalColor() {
        val compiled = compiled(
            EffectOp.SetHsv(EffectTarget.ALL, 0, 255, 255),
            EffectOp.Wait(500),
            EffectOp.FadeHsv(EffectTarget.ALL, 120, 255, 255, 1_500),
            EffectOp.FadeHsv(EffectTarget.ALL, 240, 255, 255, 1_500),
        )
        val interpreter = EffectInterpreter(compiled, groups(hue = 30))

        assertEquals(0, interpreter.frameAt(0).groups.first().hue)
        assertTrue(interpreter.frameAt(499).waiting)
        assertEquals(60, interpreter.frameAt(1_250).groups.first().hue)
        assertEquals(120, interpreter.frameAt(2_000).groups.first().hue)
        val finalFrame = interpreter.frameAt(3_500)
        assertEquals(240, finalFrame.groups.first().hue)
        assertTrue(finalFrame.finished)
    }

    @Test
    fun forLoopUsesNumberVariableAndUpdatesHueAtEachYield() {
        val variable = "hue-index"
        val compiled = CompiledEffect(
            operations = listOf(
                EffectOp.For(
                    variable,
                    number(0),
                    number(10),
                    number(5),
                    listOf(
                        EffectOp.SetHsv(
                            EffectTarget.ALL,
                            EffectExpression.Variable(variable, EffectValueType.NUMBER),
                            number(255),
                            number(255),
                        ),
                        EffectOp.Wait(100),
                    ),
                ),
            ),
            blockCount = 4,
            estimatedDurationMs = 300,
            astSha256 = "",
            variables = mapOf(variable to EffectValueType.NUMBER),
        )
        val interpreter = EffectInterpreter(compiled, groups(hue = 30))
        assertEquals(0, interpreter.frameAt(0).groups.first().hue)
        assertEquals(5, interpreter.frameAt(100).groups.first().hue)
        assertEquals(10, interpreter.frameAt(200).groups.first().hue)
        assertTrue(interpreter.frameAt(300).finished)
    }

    @Test
    fun whileConditionReadsVirtualLampState() {
        val condition = EffectExpression.Comparison(
            ComparisonOperator.LT,
            EffectExpression.GroupValue(0, EffectGroupProperty.VALUE),
            number(150),
        )
        val compiled = compiled(
            EffectOp.While(
                condition,
                listOf(
                    EffectOp.AdjustHsv(EffectTarget.ALL, 0, 0, 50),
                    EffectOp.Wait(100),
                ),
            ),
        )
        val interpreter = EffectInterpreter(compiled, groups(hue = 0).map { it.copy(value = 0) })
        assertEquals(50, interpreter.frameAt(0).groups.first().value)
        assertEquals(100, interpreter.frameAt(100).groups.first().value)
        assertEquals(150, interpreter.frameAt(200).groups.first().value)
        assertTrue(interpreter.frameAt(300).finished)
    }

    @Test
    fun colourVariableAndIfElseUseTypedValues() {
        val colourId = "selected-colour"
        val condition = EffectExpression.Comparison(
            ComparisonOperator.GT,
            EffectExpression.GroupValue(0, EffectGroupProperty.HUE),
            number(180),
        )
        val compiled = CompiledEffect(
            operations = listOf(
                EffectOp.SetVariable(
                    colourId,
                    EffectExpression.ColourLiteral(EffectColour(120, 255, 255)),
                ),
                EffectOp.If(
                    condition,
                    listOf(EffectOp.SetColour(
                        EffectTarget.ALL,
                        EffectExpression.Variable(colourId, EffectValueType.COLOUR),
                    )),
                    listOf(EffectOp.SetHsv(EffectTarget.ALL, 0, 255, 255)),
                ),
            ),
            blockCount = 4,
            estimatedDurationMs = null,
            astSha256 = "",
            variables = mapOf(colourId to EffectValueType.COLOUR),
        )
        assertEquals(120, EffectInterpreter(compiled, groups(hue = 240)).frameAt(0).groups.first().hue)
        assertEquals(0, EffectInterpreter(compiled, groups(hue = 20)).frameAt(0).groups.first().hue)
    }

    @Test
    fun zeroTimeWhileLoopIsStoppedByInstructionBudget() {
        val compiled = compiled(
            EffectOp.While(
                EffectExpression.BooleanLiteral(true),
                listOf(EffectOp.AdjustHsv(EffectTarget.ALL, 1, 0, 0)),
            ),
        )
        assertThrows(EffectRuntimeException::class.java) {
            EffectInterpreter(compiled, groups(hue = 0)).frameAt(0)
        }
    }

    @Test
    fun breakAndContinueControlTheNearestForLoop() {
        val index = "index"
        val indexValue = EffectExpression.Variable(index, EffectValueType.NUMBER)
        fun equals(value: Int) = EffectExpression.Comparison(
            ComparisonOperator.EQ, indexValue, number(value),
        )
        val compiled = CompiledEffect(
            operations = listOf(
                EffectOp.For(
                    index, number(0), number(5), number(1),
                    listOf(
                        EffectOp.If(equals(2), listOf(EffectOp.Continue()), emptyList()),
                        EffectOp.If(equals(4), listOf(EffectOp.Break()), emptyList()),
                        EffectOp.AdjustHsv(EffectTarget.ALL, 10, 0, 0),
                        EffectOp.Wait(50),
                    ),
                ),
            ),
            blockCount = 8,
            estimatedDurationMs = null,
            astSha256 = "",
            variables = mapOf(index to EffectValueType.NUMBER),
        )
        val final = EffectInterpreter(compiled, groups(hue = 0)).frameAt(500)
        assertEquals(30, final.groups.first().hue)
        assertTrue(final.finished)
    }

    @Test
    fun dynamicDivisionByZeroFailsSafely() {
        val divisor = "divisor"
        val compiled = CompiledEffect(
            operations = listOf(
                EffectOp.SetVariable(divisor, number(0)),
                EffectOp.Wait(
                    EffectExpression.Arithmetic(
                        ArithmeticOperator.DIVIDE,
                        number(100),
                        EffectExpression.Variable(divisor, EffectValueType.NUMBER),
                    ),
                ),
            ),
            blockCount = 3,
            estimatedDurationMs = null,
            astSha256 = "",
            variables = mapOf(divisor to EffectValueType.NUMBER),
        )
        assertThrows(EffectRuntimeException::class.java) {
            EffectInterpreter(compiled, groups(hue = 0)).frameAt(0)
        }
    }

    private fun compiled(vararg operations: EffectOp) = CompiledEffect(
        operations = operations.toList(),
        blockCount = operations.size + 1,
        estimatedDurationMs = null,
        astSha256 = "",
    )

    private fun groups(hue: Int, mode: Int = 1) =
        List(7) { GroupState(innerMode = mode, hue = hue, sat = 255, value = 255) }

    private fun number(value: Int) = EffectExpression.NumberLiteral(value.toDouble())
}
