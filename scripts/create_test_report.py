#!/usr/bin/env python3
"""Generate a blank Roblox Studio test report from the current test inventory."""

from argparse import ArgumentParser
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEST_DIR = ROOT / "src" / "server"
MANUAL_TESTS = ("CombatMultiplayerSmokeTest.server.lua",)


def main() -> None:
    parser = ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("combatapi-studio-test-report.md"),
        help="destination Markdown file (default: ./combatapi-studio-test-report.md)",
    )
    args = parser.parse_args()

    tests = sorted(path.name for path in TEST_DIR.glob("*Test.lua"))
    if not tests:
        raise SystemExit("No *Test.lua modules found")

    lines = [
        "# CombatAPI — relatório de execução no Roblox Studio",
        "",
        f"- Data da execução: {date.today().isoformat()} (preencher/confirmar)",
        "- Commit: ` `",
        "- Versão do Roblox Studio: preencher",
        "- Sistema operacional / dispositivo: preencher",
        "- Place: artefato Rojo gerado a partir de `default.project.json`",
        "- Responsável pela execução: preencher",
        "",
        "> Este documento é um modelo. Marque resultados somente após observar a execução real no Studio.",
        "> Um build Rojo bem-sucedido ou uma análise estática não equivale à aprovação dos testes de runtime.",
        "",
        "## Suíte automatizada",
        "",
        f"Total de módulos automatizados: **{len(tests)}**",
        "",
        "| Resultado | Módulo | Observações / erro relevante |",
        "|---|---|---|",
    ]
    lines.extend(f"| Pendente | `{name}` | |" for name in tests)
    lines.extend(
        [
            "",
            "## Resultado geral",
            "",
            "- [ ] Todos os módulos automatizados concluíram sem erros",
            "- [ ] `CombatDocumentationTest` concluiu",
            "- [ ] `CombatDocumentationExamplesTest` concluiu",
            "- [ ] `CombatCustomDataReplayTest` concluiu",
            "- [ ] `CombatAPIPublicContractTest` concluiu",
            "- [ ] Não houve erros não relacionados aos testes no Output",
            "",
            "## Testes manuais/separadamente condicionados",
            "",
            "| Resultado | Teste | Observações / erro relevante |",
            "|---|---|---|",
        ]
    )
    lines.extend(
        f"| Pendente | `{name}` | Requer configuração específica do Studio |"
        for name in MANUAL_TESTS
    )
    lines.extend(
        [
            "",
            "## Benchmark",
            "",
            "- `RunBenchmark`: `true`",
            "- `AttackInstanceCount`: preencher (padrão 32; máximo 128)",
            "- Ambiente e condições: preencher",
            "- Tempo de captura: preencher",
            "- Tempo de serialização: preencher",
            "- Tempo de validação: preencher",
            "- Tempo de preparação/restauração: preencher",
            "- Tamanho do snapshot sem overrides: preencher",
            "- Tamanho do snapshot com overrides: preencher",
            "- Comparação com a linha de base: preencher",
            "",
            "## Conclusão",
            "",
            "Descrever falhas, regressões, limitações e decisão de aprovação. Não declarar uma fase aprovada enquanto houver resultados pendentes.",
            "",
        ]
    )

    output = args.output if args.output.is_absolute() else ROOT / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines), encoding="utf-8")
    print(f"Generated {output} with {len(tests)} test entries")


if __name__ == "__main__":
    main()
