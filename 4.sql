--4.sql
WITH comments_final AS (
  SELECT
       id AS comment_id,
       text,
       created_at AS comment_created_at,
       last_updated_at AS comment_last_updated_at,
       created_by AS comment_created_by,
       last_updated_by AS comment_last_updated_by,
       entity_id
  FROM comments
  WHERE workspace_id = 'aef3c10f-1516-4cd0-b7d6-92213d4cfebb'
  AND project_id = '0194d02b-d735-7b34-8b7e-3b8f7e287e78'
  ORDER BY (workspace_id, project_id, entity_id, id) DESC, last_updated_at DESC
  LIMIT 1 BY id
), feedback_scores_agg AS (
    SELECT
        entity_id,
        mapFromArrays(
            groupArray(name),
            groupArray(value)
        ) as feedback_scores,
        groupArray(tuple(
             name,
             category_name,
             value,
             reason,
             source,
             created_at,
             last_updated_at,
             created_by,
             last_updated_by
        )) as feedback_scores_list
    FROM (
        SELECT
            *
        FROM feedback_scores
        WHERE entity_type = 'span'
        AND workspace_id = 'aef3c10f-1516-4cd0-b7d6-92213d4cfebb'
	    AND project_id = '0194d02b-d735-7b34-8b7e-3b8f7e287e78'
        ORDER BY (workspace_id, project_id, entity_type, entity_id, name) DESC, last_updated_at DESC
        LIMIT 1 BY entity_id, name
    )
    GROUP BY workspace_id, project_id, entity_id
)
SELECT
    s.id as id,
    s.workspace_id as workspace_id,
    s.project_id as project_id,
    s.trace_id as trace_id,
    s.parent_span_id as parent_span_id,
    s.name as name,
    s.type as type,
    s.start_time as start_time,
    s.end_time as end_time,
	replaceRegexpAll(input, '"(data:image/[^;]{3,4};base64,)?(/9j/|iVBORw0KGgo|R0lGODlh|R0lGODdh|Qk|SUkq|TU0A|UklGR)={0,2}[A-Za-z0-9+/]+={0,2}"', '"[image]"') as input , 
	replaceRegexpAll(output, '"(data:image/[^;]{3,4};base64,)?(/9j/|iVBORw0KGgo|R0lGODlh|R0lGODdh|Qk|SUkq|TU0A|UklGR)={0,2}[A-Za-z0-9+/]+={0,2}"', '"[image]"') as output , 
	replaceRegexpAll(metadata, '"(data:image/[^;]{3,4};base64,)?(/9j/|iVBORw0KGgo|R0lGODlh|R0lGODdh|Qk|SUkq|TU0A|UklGR)={0,2}[A-Za-z0-9+/]+={0,2}"', '"[image]"') as metadata ,
    s.model as model,
    s.provider as provider,
    s.total_estimated_cost as total_estimated_cost,
    s.tags as tags,
    s.usage as usage,
    s.error_info as error_info,
    s.created_at as created_at,
    s.last_updated_at as last_updated_at,
    s.created_by as created_by,
    s.last_updated_by as last_updated_by,
    s.duration as duration,
    s.feedback_scores_list as feedback_scores_list,
    s.feedback_scores as feedback_scores,
    groupArray(tuple(c.*)) AS comments
FROM (
    SELECT
          spans.*,
          if(end_time IS NOT NULL AND start_time IS NOT NULL
                   AND notEquals(start_time, toDateTime64('1970-01-01 00:00:00.000', 9)),
               (dateDiff('microsecond', start_time, end_time) / 1000.0),
               NULL) AS duration,
          fsa.feedback_scores_list as feedback_scores_list,
          fsa.feedback_scores as feedback_scores
    FROM spans
    LEFT JOIN feedback_scores_agg AS fsa ON fsa.entity_id = spans.id
    WHERE workspace_id = 'aef3c10f-1516-4cd0-b7d6-92213d4cfebb'
	AND project_id = '0194d02b-d735-7b34-8b7e-3b8f7e287e78'
    ORDER BY (workspace_id, project_id, id) DESC, last_updated_at DESC
    LIMIT 1 BY id
    LIMIT 100 OFFSET 0
) AS s
LEFT JOIN comments_final AS c ON s.id = c.entity_id
GROUP BY
  s.*
ORDER BY (workspace_id, project_id, id) DESC, last_updated_at DESC
SETTINGS 
		  use_query_cache = 0,
		  use_uncompressed_cache=0;
