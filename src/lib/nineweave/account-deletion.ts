/** Own-account erasure. Never accepts a caller-selected player ID. */
import { requirePlayer } from "./players.ts";
import { hashToken, newId } from "./security.ts";
import { ApiError, type Service } from "./service.ts";
import { pgCode, type Statement } from "./store.ts";

export async function deleteOwnAccount(svc: Service, bearer: string | null, body: Record<string, unknown>) {
  const player = await requirePlayer(svc, bearer);
  if (Object.keys(body).some((key) => key !== "confirm") || body.confirm !== "DELETE MY ACCOUNT")
    throw new ApiError(400, 'Confirm deletion with "DELETE MY ACCOUNT"');
  const target = "select id from nw_delete_target where not blocked";
  const params = [player.id, hashToken(bearer!)];
  const steps: Statement[] = [
    { text: "set local lock_timeout = '3s'" },
    // Rare destructive operation: serialize all affected writes to prevent a
    // concurrent join/result/report from recopying identity after scrubbing.
    { text: "lock table nw_players, nw_rooms, nw_matches, nw_tournaments, nw_tournament_players, nw_tournament_matches, nw_chat, nw_blocks, nw_reports, nw_email_challenges in share row exclusive mode" },
    { text: `create temporary table nw_delete_target on commit drop as
        select p.id, (
          exists(select 1 from nw_rooms r where r.status in ('waiting','active') and (r.a_player_id=p.id or r.b_player_id=p.id))
          or exists(select 1 from nw_tournaments t where t.status in ('registering','starting','running') and
            (t.host_player_id=p.id or exists(select 1 from nw_tournament_players e where e.tournament_id=t.id and e.player_id=p.id)))
        ) as blocked from nw_players p where p.id=$1 and p.token_hash=$2`, params },
    // Keep only shared gameplay facts; no replacement account or unique alias.
    { text: `update nw_rooms set status='closed', rev=$1, a_rematch=false, b_rematch=false,
        left_slot=case when a_player_id in (${target}) then 'a' else 'b' end
        where a_player_id in (${target}) or b_player_id in (${target})`, params:[newId("r")] },
    { text: `update nw_tournaments set rev=$1 where host_player_id in (${target}) or champion_player_id in (${target})
        or id in (select tournament_id from nw_tournament_players where player_id in (${target}))`, params:[newId("r")] },
    { text: `update nw_rooms set a_name='####', a_token_hash='deleted', a_rematch=false where a_player_id in (${target})` },
    { text: `update nw_rooms set b_name='####', b_token_hash=null, b_rematch=false where b_player_id in (${target})` },
    { text: `update nw_matches set x_name='####' where x_player_id in (${target})` },
    { text: `update nw_matches set o_name='####' where o_player_id in (${target})` },
    { text: `update nw_tournaments set champion_name='####' where champion_player_id in (${target})` },
    // Free text cannot safely be anonymized by name substitution. Remove the
    // whole report, including notes/snapshots, when either participant is erased.
    { text: `delete from nw_reports where reporter_id in (${target}) or reported_id in (${target})` },
    // FK CASCADE removes challenges, own chat, blocks and membership; SET NULL
    // unlinks room/match/bracket/host/champion IDs without changing results.
    { text: `delete from nw_players where id in (${target}) returning id` },
    { text: "select id, blocked from nw_delete_target" },
  ];
  let results: Record<string, unknown>[][];
  try { results = await svc.db.transaction(steps); }
  catch (err) {
    if (["55P03", "40P01", "40001"].includes(pgCode(err) ?? ""))
      throw new ApiError(503, "The account is busy. Please retry deletion shortly.");
    throw err;
  }
  const status = results.at(-1)![0];
  if (!status) throw new ApiError(401, "Your account session is no longer valid");
  if (status.blocked) throw new ApiError(409, "Leave or finish active matches. Leave registering tournaments; for started tournaments, wait until they end before deleting your account.");
  return { deleted: true, retained_gameplay_label: "####" };
}
