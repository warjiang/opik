--6.sql
WITH feedback_scores_agg AS ( 
	SELECT entity_id, mapFromArrays( groupArray(name), groupArray(value) ) as feedback_scores, 
			groupArray(tuple( name, category_name, value, reason, source, created_at, last_updated_at, created_by, last_updated_by )) as feedback_scores_list 
			FROM ( SELECT * FROM feedback_scores 
			WHERE entity_type = 'trace' 
			AND workspace_id = 'aef3c10f-1516-4cd0-b7d6-92213d4cfebb'
	        AND project_id = '019479e2-61ef-7c98-836e-f4cec3ab69e8'
			ORDER BY (workspace_id, project_id, entity_type, entity_id, name) DESC, last_updated_at DESC 
			LIMIT 1 BY entity_id, name ) 
	GROUP BY workspace_id, project_id, entity_id )
, spans_agg AS ( 
	SELECT trace_id, sumMap(usage) as usage, 
			sum(total_estimated_cost) as total_estimated_cost, 
			COUNT(DISTINCT id) as span_count 
	FROM spans
    WHERE workspace_id = 'aef3c10f-1516-4cd0-b7d6-92213d4cfebb'
	AND project_id = '019479e2-61ef-7c98-836e-f4cec3ab69e8'
    GROUP BY workspace_id, project_id, trace_id
)
, comments_agg AS ( 
	SELECT entity_id, groupArray(tuple(id, text, created_at, last_updated_at, created_by, last_updated_by)) AS comments_array 
	FROM ( 
		SELECT id, text, created_at, last_updated_at, created_by, last_updated_by, entity_id, workspace_id, project_id FROM comments
		WHERE workspace_id = 'aef3c10f-1516-4cd0-b7d6-92213d4cfebb'
	    AND project_id = '019479e2-61ef-7c98-836e-f4cec3ab69e8'
		ORDER BY (workspace_id, project_id, entity_id, id) DESC, last_updated_at DESC 
		LIMIT 1 BY id 
	) GROUP BY workspace_id, project_id, entity_id ) 
SELECT t.id as id, 
		t.workspace_id as workspace_id, 
		t.project_id as project_id,
		t.name as name, 
		t.start_time as start_time, 
		t.end_time as end_time, 
		replaceRegexpAll(input, '"(data:image/[^;]{3,4};base64,)?(/9j/|iVBORw0KGgo|R0lGODlh|R0lGODdh|Qk|SUkq|TU0A|UklGR)={0,2}[A-Za-z0-9+/]+={0,2}"', '"[image]"') as input , 
		replaceRegexpAll(output, '"(data:image/[^;]{3,4};base64,)?(/9j/|iVBORw0KGgo|R0lGODlh|R0lGODdh|Qk|SUkq|TU0A|UklGR)={0,2}[A-Za-z0-9+/]+={0,2}"', '"[image]"') as output , 
		replaceRegexpAll(metadata, '"(data:image/[^;]{3,4};base64,)?(/9j/|iVBORw0KGgo|R0lGODlh|R0lGODdh|Qk|SUkq|TU0A|UklGR)={0,2}[A-Za-z0-9+/]+={0,2}"', '"[image]"') as metadata , 
		t.tags as tags, 
		t.error_info as error_info, 
		t.created_at as created_at, 
		t.last_updated_at as last_updated_at, 
		t.created_by as created_by, 
		t.last_updated_by as last_updated_by, 
		t.duration as duration, 
		t.thread_id as thread_id, 
		t.feedback_scores_list as feedback_scores_list, 
		t.feedback_scores as feedback_scores, 
		sumMap(s.usage) as usage, 
		sum(s.total_estimated_cost) as total_estimated_cost, 
		groupUniqArrayArray(c.comments_array) as comments, 
		max(s.span_count) AS span_count 
FROM ( 
	SELECT 
		t.*, if(end_time IS NOT NULL AND start_time IS NOT NULL AND notEquals(start_time, toDateTime64('1970-01-01 00:00:00.000', 9)), (dateDiff('microsecond', start_time, end_time) / 1000.0), NULL) AS duration, 
		fsagg.feedback_scores_list as feedback_scores_list, 
		fsagg.feedback_scores as feedback_scores 
	FROM traces t 
	LEFT JOIN feedback_scores_agg fsagg ON fsagg.entity_id = t.id
	WHERE workspace_id = 'aef3c10f-1516-4cd0-b7d6-92213d4cfebb'
	AND project_id = '019479e2-61ef-7c98-836e-f4cec3ab69e8'
	ORDER BY (workspace_id, project_id, id) DESC, last_updated_at DESC 
	LIMIT 1 BY id 
	LIMIT 100 OFFSET 0 
) AS t 
LEFT JOIN spans_agg AS s ON t.id = s.trace_id 
LEFT JOIN comments_agg AS c ON t.id = c.entity_id 
GROUP BY t.* 
ORDER BY (workspace_id, project_id, id) DESC, last_updated_at DESC 
;