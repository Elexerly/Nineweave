import { createFileRoute } from "@tanstack/react-router";
import { LegalPage } from "@/components/legal-page";
import markdown from "../../legal/terms.md?raw";

export const Route = createFileRoute("/terms")({
  head: () => ({
    meta: [
      { title: "Terms of Service — Nineweave" },
      {
        name: "description",
        content: "Terms of Service for Nineweave, the Ultimate Tic Tac Toe game.",
      },
    ],
  }),
  component: TermsPage,
});

function TermsPage() {
  return <LegalPage markdown={markdown} />;
}
