public with sharing class SobjectUtils {
	/**
	* Extracts IDs from collection of SObjects.
	*
	* @param sobjs collection of SObjects to extract IDs from
	*
	* @return a set of SObject IDs
	*/
	public static Set<Id> extractIds(List<SObject> sobjs) {
		return extractIds(sobjs, 'Id');
	}
	
	/**
	* Extracts IDs from a particular field in collection of SObjects.
	*
	* @param sobjs collection of SObjects to extract IDs from
	* @param relationshipField an ID field for values to be extracted from
	*
	* @return a set of IDs from given relationship field from given SObjects
	*/
	public static Set<Id> extractIds(List<SObject> sobjs, SObjectField relationshipField) {
		return extractIds(sobjs, relationshipField.getDescribe().getName());
	}
	
	/**
	* Extracts IDs from a particular field in collection of SObjects.
	*
	* @param sobjs collection of SObjects to extract IDs from
	* @param relationshipFieldName API name of the field for IDs to be extracted from
	*
	* @return a set of IDs from given relationship field from given SObjects
	*/
	public static Set<Id> extractIds(List<SObject> sobjs, String relationshipFieldName) {
		Set<Id> values = new Set<Id>();
		for (SObject sobj : sobjs) {
			values.add((Id) sobj.get(relationshipFieldName));
		}
		return values;
	}
	
	/**
	* Extracts field values from a particular field in collection of SObjects.
	*
	* @param sobjs collection of SObjects to extract field values from
	* @param field a field for values to be extracted from
	*
	* @return a set of values from given field from given SObjects
	*/
	public static Set<Object> extractValues(List<SObject> sobjs, SObjectField field) {
		return extractValues(sobjs, field.getDescribe().getName());
	}
	
	/**
	* Extracts field values from a particular field in collection of SObjects.
	*
	* @param sobjs collection of SObjects to extract field values from
	* @param fieldName API name of the field for values to be extracted from
	*
	* @return a set of values from given field from given SObjects
	*/
	public static Set<Object> extractValues(List<SObject> sobjs, String fieldName) {
		Set<Object> values = new Set<Object>();
		for (SObject sobj : sobjs) {
			values.add(sobj.get(fieldName));
		}
		return values;
	}
	
	/**
	* Checks if junction objects to be saved in database do not form multiple junctions between same parents.
	* Otherwise, adds errors to offending records.
	* To be used on after insert and after undelete trigger events, and, in case of reparentable junction object, on after update.
	* Relies on the fact that on after trigger event new records are already in database and can be queries together with old records.
	* An alternative to relying on unique field that concatenates parents' IDs.
	* Order of given parent fields does not matter.
	*
	* @param junctionObjs collection of junction objects to be validated
	* @param parentField1 one of the parent fields
	* @param parentField2 another one of the parent fields
	*/
	public static void checkJunctionUniqueness(List<SObject> junctionObjs, SObjectField parentField1, SObjectField parentField2) {
		final String parentField1Name = parentField1.getDescribe().getName();
		final String parentField2Name = parentField2.getDescribe().getName();
		List<AggregateResult> aggregatedMultipleJunctionCount = findMultipleSiblingJunctionObjectCount(junctionObjs, parentField1Name, parentField2Name);
		Set<Object> parentPairsWithMultipleJunctionCount = fetchParentPairs(aggregatedMultipleJunctionCount, parentField1Name, parentField2Name);
		
		for (SObject jo : junctionObjs) {
			if (parentPairsWithMultipleJunctionCount.contains(createParentsCompoundKey(jo, parentField1Name, parentField2Name))) {
				jo.addError(Label.ParentsAlreadyJoint);
			}
		}
	}
	
	/**
	* Calculates count of all junction objects under both parents of given junction objects; reports only count of multiple junction objects per parent pair.
	* Order of given parent fields' names does not matter.
	*
	* @param junctionObjs collection of junction objects to select siblings of
	* @param parentField1Name name of one of the parent fields
	* @param parentField2Name name of another of the parent fields
	*
	* @return list of AggregateResults with junction object count (only exceeding 1), grouped by both parents
	*/
	private static List<AggregateResult> findMultipleSiblingJunctionObjectCount(List<SObject> junctionObjs, String parentField1Name, String parentField2Name) {
		Set<Id> parent1Ids = SobjectUtils.extractIds(junctionObjs, parentField1Name);
		Set<Id> parent2Ids = SobjectUtils.extractIds(junctionObjs, parentField2Name);
		final String junctionObjName = junctionObjs.getSObjectType().getDescribe().getName();
		return findMultipleJunctionObjectCountByParentIds(junctionObjName, parentField1Name, parentField2Name, parent1Ids, parent2Ids);
	}
	
	/**
	* Calculates count of junction objects by specified parent IDs; reports only count of multiple junction objects per parent pair.
	* Order of given parent fields' names does not matter.
	*
	* @param junctionObjName junction object name
	* @param parentField1Name name of one of the parent fields
	* @param parentField2Name name of another of the parent fields
	* @param parent1Ids collection of IDs of one parent
	* @param parent2Ids collection of IDs of another parent
	*
	* @return list of AggregateResults with junction object count (only exceeding 1), grouped by both parents
	*/
	private static List<AggregateResult> findMultipleJunctionObjectCountByParentIds(
		String junctionObjName,
		String parentField1Name,
		String parentField2Name,
		Set<Id> parent1Ids,
		Set<Id> parent2Ids
	) {
		final String query = 'SELECT COUNT(Id), ' + parentField1Name + ', ' + parentField2Name +
			' FROM ' + junctionObjName +
			' GROUP BY ' + parentField1Name + ', ' + parentField2Name +
			' HAVING COUNT(Id) > 1' +
			' AND ' + parentField1Name + ' IN :parent1Ids' +
			' AND ' + parentField2Name + ' IN :parent2Ids'
		;
		return Database.query(query);
	}
	
	/**
	* Creates a set of parent pairs from given AggregateResults.
	* Order of given parent fields' names does matter.
	*
	* @param aggregatedJunctionCount collection of junction objects to be mapped
	* @param parentField1Name name of one of the parent fields
	* @param parentField2Name name of another of the parent fields
	*
	* @return a set of parent pairs
	*/
	private static Set<Object> fetchParentPairs(List<AggregateResult> aggregatedJunctionCount, String parentField1Name, String parentField2Name) {
		Set<Object> parentPairs = new Set<Object>();
		for (AggregateResult ar : aggregatedJunctionCount) {
			parentPairs.add(createParentsCompoundKey(ar, parentField1Name, parentField2Name));
		}
		return parentPairs;
	}
	
	/**
	* Creates a compound key from an SObject (junction object or AggregateResult) and its parents' IDs.
	* Order of given parent fields' names does matter.
	*
	* @param sobj SObject (junction object or AggregateResult) to get parents from
	* @param parentField1Name name of one of the parent fields
	* @param parentField2Name name of another of the parent fields
	*
	* @return compound key with both parents' IDs
	*/
	private static Object createParentsCompoundKey(SObject sobj, String parentField1Name, String parentField2Name) {
		final String parent1Id = (String) sobj.get(parentField1Name);
		final String parent2Id = (String) sobj.get(parentField2Name);
		return parent1Id + parent2Id;
	}
	
	/**
	* Summarizes changes in child records' values, grouped by parent ID.
	* If delta is zero, the change is not reported.
	* To be used to summarize value on parent, on after trigger event, when roll-up summary is unavailable (such as with lookup relationship).
	*
	* @param newRecords list of changed SObjects (from trigger)
	* @param oldRecords list of old SObjects (from trigger)
	* @param childValueField field on child object to be summarized
	* @param childParentField parent relationship field
	*
	* @return a map with parent ID as key and decimal summarized value
	*/
	public static Map<Id, Decimal> summarizeChangesOnParentValue(
		List<SObject> newRecords,
		List<SObject> oldRecords,
		SObjectField childValueField,
		SObjectField childParentField
	) {
		Map<Id, Decimal> parentIdToValueDelta = new Map<Id, Decimal>();
		if (newRecords != null) {
			summarizeChangesOnParentValue(newRecords, childValueField, childParentField, parentIdToValueDelta, 1);
		}
		if (oldRecords != null) {
			summarizeChangesOnParentValue(oldRecords, childValueField, childParentField, parentIdToValueDelta, -1);
		}
		for (Id parentId : parentIdToValueDelta.keySet()) {
			if ((Decimal) parentIdToValueDelta.get(parentId) == 0) {
				parentIdToValueDelta.remove(parentId);
			}
		}
		return parentIdToValueDelta;
	}
	
	/**
	* Summarizes changes in child records' values, grouped by parent ID.
	* Modifies given map of parent ID to sum in place.
	* Summarized values are multiplied by a given multiplier. It can be used to subtract values from old records (i.e. add with multiplier -1).
	*
	* @param records collection of child records to be summarized
	* @param childValueField field on child object to be summarized
	* @param childParentField parent relationship field
	* @param parentIdToValueDelta existing map of parent ID to sum
	* @param multiplier value by which child values will be multiplied by
	*/
	private static void summarizeChangesOnParentValue(List<SObject> records,
		SObjectField childValueField,
		SObjectField childParentField,
		Map<Id, Decimal> parentIdToValueDelta,
		Integer multiplier
	) {
		for (SObject child : records) {
			final Id parentId = (Id) child.get(childParentField);
			if (!parentIdToValueDelta.containsKey(parentId)) {
				parentIdToValueDelta.put(parentId, 0);
			}
			parentIdToValueDelta.put(
				parentId,
				parentIdToValueDelta.get(parentId) + multiplier * (Decimal) child.get(childValueField)
			);
		}
	}
}