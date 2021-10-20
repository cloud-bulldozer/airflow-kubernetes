def index_report(es_client, report, target_index):
    doc_id = report['metadata']['uuid']
    response = es_client.index(
            index=target_index,
            id=doc_id,
            body=report
        )

    return response